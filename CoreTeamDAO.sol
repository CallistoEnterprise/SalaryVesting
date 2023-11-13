// SPDX-License-Identifier: No License (None)
pragma solidity 0.8.19;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable {
    address internal _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     *//*
    constructor () {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }
    */

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface ISoyPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast); 
}

interface IERC20 {
    function balanceOf(address owner) external view returns (uint);
    function transfer(address to, uint value) external;
}

contract CoreTeamDAO is Ownable {
    ISoyPair constant public CLO_BUSDT = ISoyPair(0xB852AD87329986EaC6e991954fe329231D1E4De1);    // reserve0 - BUSDT, reserve1 - WCLO
    uint256 constant public salaryPeriod = 30 days;   // salary period in seconds
    uint256 constant public quarterlyPeriod = 91 days;    // period in seconds for quarterly payment 
    uint256 constant public yearlyPeriod = 365 days;    // period in seconds for yearly payment


    struct Employee {
        uint256 startTimestamp;  // timestamp from which start periods
        uint256 lastClaimed; // timestamp when CLO was claimed last time
        uint256 salary; // salary in BUSDT (without decimals)
        uint256 quarterlyPercent; // percent of salary paid quarterly
        uint256 yearlyPercent; // percent of salary paid yearly
        uint256 quarterlyPending; // Amount of CLO that is pending for quarterly payout
        uint256 yearlyPending; // Amount of CLO that is pending for yearly payout
        uint256 unpaid; // Amount of CLO that was not paid due to insufficient contract balance
        bool isStopped;  // stop payouts
    }

    mapping (address => Employee) public employees;
    address[] public employeesList; // list of employees
    bool public isPaused;

    event SetSalary(address employee, uint256 salary, uint256 quarterlyPercent, uint256 yearlyPercent, uint256 startTimestamp);
    event Claim(uint256 amount, uint256 pendingAmount);
    event Rescue(address token, uint256 amount);


    function initialize(address _newOwner) external {
        require(_owner == address(0));
        _owner = _newOwner;
        emit OwnershipTransferred(address(0), _newOwner);
    }

    receive() external payable {}

    // Set salary in BUSDT without decimals. if "startTimestamp" == 0, then startTimestamp will not be updated
    function setSalary(address employee, uint256 salary, uint256 quarterlyPercent, uint256 yearlyPercent, uint256 startTimestamp) external onlyOwner {
        require(quarterlyPercent + yearlyPercent < 100, "Sum of percents must be less 100");
        if (!isPaused && !employees[employee].isStopped) _claim(employee);   // claim unlocked salary and bonus to employee address
        if(employees[employee].lastClaimed == 0) {
            // new employee
            employeesList.push(employee);
        }
        if (startTimestamp > 0) {
            employees[employee].startTimestamp = startTimestamp;
            employees[employee].lastClaimed = startTimestamp;
        }
        employees[employee].salary = salary;
        employees[employee].quarterlyPercent = quarterlyPercent;
        employees[employee].yearlyPercent = yearlyPercent;

        emit SetSalary(employee, salary, quarterlyPercent, yearlyPercent, startTimestamp);
    }

    // pause/unpause contract
    function setPause(bool pause) external onlyOwner {
        isPaused = pause;
    }

    // stop employee payment 
    function setStop(address employee, bool stopped) external onlyOwner {
        employees[employee].isStopped = stopped;
    }

    // claim unlocked salary and bonus to employee address
    function claim() external {
        require(tx.origin == msg.sender, "Call from contract disallowed");  // protection from flash-loan price manipulation
        require(!isPaused, "Payout paused");
        require(!employees[msg.sender].isStopped, "Payment is stopped by owner");
        _claim(msg.sender);
    }

    function _claim(address employee) internal {
        (uint256 unlockedAmount, uint256 quarterlyPending, uint256 yearlyPending) = getUnlockedAmount(employee);
        if (unlockedAmount != 0) {
            uint256 balance = address(this).balance;
            if (unlockedAmount > balance) {
                employees[employee].unpaid = unlockedAmount - balance;
                unlockedAmount = balance;
            } else {
                employees[employee].unpaid = 0;
            }
            employees[employee].lastClaimed = block.timestamp;
            employees[employee].quarterlyPending = quarterlyPending;
            employees[employee].yearlyPending = yearlyPending;
            safeTransferCLO(employee, unlockedAmount);
            emit Claim(unlockedAmount, employees[employee].unpaid);
        }
    }


    // return unlocked amount of CLO
    function getUnlockedAmount(address employee) public view returns(uint256 unlockedAmount, uint256 quarterlyPending, uint256 yearlyPending) {
        Employee memory e = employees[employee];

        uint256 salaryCLO;
        // calculate CLO amount for salary based on CLO_BUSDT pool
        {
        (uint112 reserveBUSDT, uint112 reserveCLO,) = CLO_BUSDT.getReserves();
        salaryCLO = e.salary * 1e18 * reserveCLO / reserveBUSDT; // convert salary from BUSDT to CLO and add 18 decimals
        }

        uint256 paidPeriods = (e.lastClaimed - e.startTimestamp) / salaryPeriod;
        uint256 passedPeriods = (block.timestamp - e.startTimestamp) / salaryPeriod;
        uint256 unpaidPeriods = passedPeriods - paidPeriods;
        unlockedAmount = salaryCLO * unpaidPeriods * (100 - e.quarterlyPercent - e.yearlyPercent) / 100; // unlocked salary
        e.quarterlyPending += (salaryCLO * unpaidPeriods * e.quarterlyPercent / 100);   // add part of salary to quarterlyPending
        e.yearlyPending += (salaryCLO * unpaidPeriods * e.yearlyPercent / 100); // add part of salary to yearlyPending

        // calculate amount for quarterly part
        uint256 periodEnd = e.startTimestamp + (((block.timestamp - e.startTimestamp) / quarterlyPeriod ) * quarterlyPeriod); // timestamp when last quarterly period ended
        if (periodEnd > e.lastClaimed && periodEnd <= block.timestamp ) {  // quarterly period ends
            unpaidPeriods = passedPeriods - ((periodEnd - e.startTimestamp) / salaryPeriod); // number of months excluded from quarterly payment
            quarterlyPending = (salaryCLO * unpaidPeriods * e.quarterlyPercent / 100);
            unlockedAmount += e.quarterlyPending - quarterlyPending;
        } else {
            quarterlyPending = e.quarterlyPending;
        }

        // calculate amount for yearly part
        periodEnd = e.startTimestamp + (((block.timestamp - e.startTimestamp) / yearlyPeriod ) * yearlyPeriod); // timestamp when last yearly period ended
        if (periodEnd > e.lastClaimed && periodEnd <= block.timestamp ) {  // yearly period ends
            unpaidPeriods = passedPeriods - ((periodEnd - e.startTimestamp) / salaryPeriod); // number of months excluded from yearly payment
            yearlyPending = (salaryCLO * unpaidPeriods * e.yearlyPercent / 100);
            unlockedAmount += e.yearlyPending - yearlyPending;
        } else {
            yearlyPending = e.yearlyPending;
        }

        unlockedAmount += e.unpaid;   // if contract has debt
    }

    // return allocated amount of CLO
    function getAllocatedAmount() external view returns(int256 allocatedToClaim, int256 totalAllocated) {
        uint256 len = employeesList.length;
        allocatedToClaim = int256(address(this).balance);
        uint256 totalUnlocked;
        uint256 totalPending;
        for (uint i = 0; i < len; i++) {
            if (!employees[employeesList[i]].isStopped) {   // don't count employees with stopped payouts
                (uint256 unlocked, uint256 quarterlyPending, uint256 yearlyPending) = getUnlockedAmount(employeesList[i]);
                totalUnlocked += unlocked;
                totalPending = totalPending + quarterlyPending + yearlyPending;
            }
        }
        allocatedToClaim = allocatedToClaim - int256(totalUnlocked);
        totalAllocated = allocatedToClaim - int256(totalPending);
    }

    function getEmployeesList() external view returns(address[] memory) {
        return employeesList;
    }

    function rescueTokens(address _token) onlyOwner external {
        uint256 amount;
        if (_token == address(0)) {
            amount = address(this).balance;
            safeTransferCLO(msg.sender, amount);
        } else {
            amount = IERC20(_token).balanceOf(address(this));
            safeTransfer(_token, msg.sender, amount);
        }

        emit Rescue(_token, amount);
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferCLO(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: CLO_TRANSFER_FAILED');
    }
}
