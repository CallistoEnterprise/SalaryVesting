# SalaryVesting

Salary Vasting contract allows to allocation specific amount of CLO for an employee and pays his salary and bonuses from this amount every specific period of time.
Salary and bonuses are set in BUSTD, so payouts in CLO are calculated based on Soy.Finance CLO-BUSDT pool (fee and slippage isn't counted).

To allocate CLO for an employee it should be transferred to his Salary Vasting contract.

On deployment should be set:
- `_employee` - address of employee wallet
- `_salary` - salary in BUSDT without decimals (i.e. 1000 means 1000 BUSDT). Salary can be claimed each `salaryPeriod` (30 days by default).
- `_bonus` - bonus in BUSDT without decimals. Bonus can be claimed each `bonusPeriod ` (91 days by default).
- `_startTimestamp` - UNIX timestamp from which start each period.
- `_newOwner` - address of the owner, who can change parameters and withdraw tokens from the contract.

### The owner can:
- change employee address, salary and bonus amounts
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L114-L115

- change start timestamp, salary and bonus periods
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L123-L124

- pause/unpause employee payouts
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L134

- rescue any tokens / CLO from the contract
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L187

### An employee can:

- Claim CLO for completed periods.
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L139-L140

- View the unlocked amount of CLO (that he can claim). But if the contract has less CLO than the unlocked amount, he will claim all available CLO from the contract.
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L159-L160

- View the allocated amount of CLO (which is `contract balance - unlocked amount`).
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L179-L180
