# CoreTeamDAO

[CoreTeamDAO](https://explorer.callisto.network/address/0xEc43593c62eA57F749eE0D44bE2e982C8eCb51A1/transactions) manage employees payments accordingly rules. 

Company sets an employee salary in USD, and sets payouts rules: the percentage of salary that pays monthly, quarterly, yearly.

When an employee claim payment, the salary converts from USD to CLO by current CLO/BUSDT price on the Soy.Finance, then amount in CLO splits amount monthly, quarterly, and yearly parts.

For example, if salary is 1000 USD, and it splits by 20/40/40 for monthly/quarterly/yearly payments accordingly, and CLO price is 0.001 USD, then on claim an employee receives 200K CLO instantly, and 400K will be locked for quarterly payment, and 400K will be locked for yearly payment.

Transferring to CLO to contract address add it to payouts budget.

## Main functions

### claim

Allow to employee to [claim](https://explorer.callisto.network/address/0xEc43593c62eA57F749eE0D44bE2e982C8eCb51A1/write-proxy) unlocked CLO, and fix CLO/USD price on moment of claim.

### getUnlockedAmount

Using function [getUnlockedAmount](https://explorer.callisto.network/address/0xEc43593c62eA57F749eE0D44bE2e982C8eCb51A1/read-proxy) an employee can see, how much CLO is unlocked and how much is reserved for quarterly and yearly payment (he should enter his address in the parameter field). This function shows estimated amount on moment of call. It uses current CLO price from SOY finance. After `claim` the CLO price will be fixed.

### employees

The function [employees](https://explorer.callisto.network/address/0xEc43593c62eA57F749eE0D44bE2e982C8eCb51A1/read-proxy) returns info about specific employee.

## Owner's privileges  

The owner of CoreTeamDAO is a [multisig](https://explorer.callisto.network/address/0xC7B38729e6939E406B4E3154B38B71F51e400DEf/read-contract) contract and it can:

1. Rescue all CLO or tokens from contract.
2. Change employee's salary, start time, percentage for monthly/quarterly/yearly payments.
3. Stop payment for specific employee.
4. Pause entire contract (stop payments for all).
5. Upgrade contract.



# SalaryVesting

Salary Vasting contract allows to allocation specific amount of CLO for an employee and pays his salary and bonuses from this amount every specific period of time.
Salary and bonuses are set in BUSTD, so payouts in CLO are calculated based on Soy.Finance CLO-BUSDT pool (fee and slippage isn't counted).

To allocate CLO for an employee it should be transferred to his Salary Vasting contract.

If the contract has less CLO than should be paid to the employee, then all available CLO will be transferred to the employee and the rest will be saved to the `pending` variable. 

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

- rescue any tokens / CLO from the contract (to rescue CLO, the `_token` should be `0x0000000000000000000000000000000000000000`)
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L187

### An employee can:

- Claim CLO for completed periods.
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L139-L140

- View the unlocked amount of CLO (that he can claim). But if the contract has less CLO than the unlocked amount, he will claim all available CLO from the contract.
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L159-L160

- View the allocated amount of CLO (which is `contract balance - unlocked amount`).
https://github.com/CallistoEnterprise/SalaryVesting/blob/bc363d04de8fc3d815f8e40838be2072a9304870/SalaryVesting.sol#L179-L180
