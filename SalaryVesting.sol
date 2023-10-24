// SPDX-License-Identifier: No License (None)
pragma solidity ^0.8.0;

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

contract SalaryVesting is Ownable {

    ISoyPair constant public CLO_BUSDT = ISoyPair(0xB852AD87329986EaC6e991954fe329231D1E4De1);    // reserve0 - BUSDT, reserve1 - WCLO


    address public employee;    // address of employee who can claim CLO
    uint256 public startTimestamp;  // timestamp from which start periods
    uint256 public lastClaimed; // timestamp when CLO was claimed last time
    uint256 public salary; // salary in BUSDT (without decimals)
    uint256 public salaryPeriod = 30;   // salary period in days
    uint256 public bonus; // bonus in BUSDT (without decimals)
    uint256 public bonusPeriod = 91;    // period in days for bonus
    uint256 public yearlyBonus; // yearly bonus in BUSDT (without decimals)
    uint256 public yearlyBonusPeriod = 365;    // period in days for yearly bonus
    uint256 public pending; // Amount of CLO that is pending due to insufficient CLO balance
    bool public isPaused;

    event SetSalary(address _employee, uint256 _salary, uint256 _bonus, uint256 _yearlyBonus);
    event SetPeriods(uint256 _salaryPeriod, uint256 _bonusPeriod, uint256 _yearlyBonusPeriod, uint256 _startTimestamp);
    event Claim(uint256 amount, uint256 pendingAmount);

    event Rescue(address _token, uint256 _amount);


    constructor (address _employee, uint256 _salary, uint256 _bonus, uint256 _yearlyBonus, uint256 _startTimestamp, address _newOwner) {
        require(_startTimestamp != 0);
        startTimestamp = _startTimestamp;
        lastClaimed = _startTimestamp;
        employee = _employee;
        salary = _salary;
        bonus = _bonus;
        yearlyBonus = _yearlyBonus;
        emit SetSalary(_employee, _salary, _bonus, _yearlyBonus);
        _owner = _newOwner;
        emit OwnershipTransferred(address(0), _newOwner);
    }

    receive() external payable {}

    // Set salary in BUSDT without decimals
    function setSalary(address _employee, uint256 _salary, uint256 _bonus, uint256 _yearlyBonus) external onlyOwner {
        if (!isPaused) _claim();   // claim unlocked salary and bonus to employee address
        employee = _employee;
        salary = _salary;
        bonus = _bonus;
        yearlyBonus = _yearlyBonus;
        emit SetSalary(_employee, _salary, _bonus, _yearlyBonus);
    }

    // Set periods in days and start timestamp
    function setPeriods(uint256 _salaryPeriod, uint256 _bonusPeriod, uint256 _yearlyBonusPeriod, uint256 _startTimestamp) external onlyOwner {
        if (!isPaused) _claim();   // claim unlocked salary and bonus to employee address
        salaryPeriod = _salaryPeriod;
        bonusPeriod = _bonusPeriod;
        yearlyBonusPeriod = _yearlyBonusPeriod;
        startTimestamp = _startTimestamp;
        lastClaimed = _startTimestamp;

        emit SetPeriods(_salaryPeriod, _bonusPeriod, _yearlyBonusPeriod, _startTimestamp);
    }

    function setPause(bool pause) external onlyOwner {
       isPaused = pause;
    }


    // claim unlocked salary and bonus to employee address
    function claim() external {
        require(!isPaused, "Payout paused");
        require(msg.sender == employee, "Only employee");
        _claim();
    }

    function _claim() internal {
        uint256 unlockedAmount = getUnlockedAmount();
        if (unlockedAmount != 0) {
            uint256 balance = address(this).balance;
            if (unlockedAmount > balance) {
                pending = unlockedAmount - balance;
                unlockedAmount = balance;
            } else {
                pending = 0;
            }
            lastClaimed = block.timestamp;
            safeTransferCLO(employee, unlockedAmount);
            emit Claim(unlockedAmount, pending);
        }
    }


    // return unlocked amount of CLO
    function getUnlockedAmount() public view returns(uint256 unlockedAmount) {
        unlockedAmount = pending;   // if contract has debt

        // calculate BUSDT amount for salary 
        uint256 paidPeriods = (lastClaimed - startTimestamp) / (salaryPeriod * 1 days);
        uint256 passedPeriods = (block.timestamp - startTimestamp) / (salaryPeriod * 1 days);
        uint256 unpaidPeriods = passedPeriods - paidPeriods;
        uint256 pendingBUSDT = unpaidPeriods * salary;   // pending amount in BUSDT

        // calculate BUSDT amount for bonus 
        paidPeriods = (lastClaimed - startTimestamp) / (bonusPeriod * 1 days);
        passedPeriods = (block.timestamp - startTimestamp) / (bonusPeriod * 1 days);
        unpaidPeriods = passedPeriods - paidPeriods;
        pendingBUSDT += (unpaidPeriods * bonus);     // pending amount in BUSDT

        // calculate BUSDT amount for yearly bonus 
        paidPeriods = (lastClaimed - startTimestamp) / (yearlyBonusPeriod * 1 days);
        passedPeriods = (block.timestamp - startTimestamp) / (yearlyBonusPeriod * 1 days);
        unpaidPeriods = passedPeriods - paidPeriods;
        pendingBUSDT += (unpaidPeriods * yearlyBonus);     // pending amount in BUSDT
        
        pendingBUSDT = pendingBUSDT * 1e18; // add decimals

        // calculate CLO amount based on CLO_BUSDT pool
        (uint112 reserveBUSDT, uint112 reserveCLO,) = CLO_BUSDT.getReserves();
        unlockedAmount += (pendingBUSDT * reserveCLO / reserveBUSDT);
    }

    // return allocated amount of CLO
    function getAllocatedAmount() public view returns(uint256 amount) {
        amount = address(this).balance;
        uint256 unclaimed = getUnlockedAmount();
        if (amount > unclaimed) amount = amount - unclaimed;
        else amount = 0;
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
