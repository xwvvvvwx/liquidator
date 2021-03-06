pragma solidity ^0.4.24;

import "sai/tub.sol";
import "ds-math/math.sol";
import "ds-value/value.sol";

contract Liquidator is DSMath {

    SaiTub tub;
    uint256 public collateral;
    uint256 public debt;
    uint256 public price;
    uint256 public totalValue;
    uint256 public fee;
    uint256 public surplus;

    // five percent
    uint cut = mul(5, rpow(10, 25));

    // the amount raised, in dai
    uint raised;
    // dai balances
    mapping (address => uint) public balances;

    DSToken constant dai = DSToken(0xC4375B7De8af5a38a93548eb8453a498222C4fF2);

    constructor(SaiTub _tub) public {
        tub = _tub;
        tub.gem().approve(address(tub), uint256(-1));
        tub.skr().approve(address(tub), uint256(-1));
    }

    event Owner();
    event RetrievedData(uint collateral, uint debt, uint price);
    event Calculated(uint totalValue, uint fee, uint surplus);
    event Shut();
    event Transfered();
    event Funded(address _address, uint amount, uint total);
    event Paid(address _address, uint amount);

    function close(bytes32 _cup) public {
        // can only operate on cdps that it controls
        assert(tub.lad(_cup) == address(this));

        emit Owner();

        // calcuate surplus collateral
        collateral = tub.ink(_cup);
        debt = tub.tab(_cup);
        price = tub.tag();
        emit RetrievedData(collateral, debt, price);

        // dollars :)
        totalValue = rmul(collateral, price);
        fee = rmul(totalValue, cut);
        surplus = sub(sub(totalValue, fee), debt);
        emit Calculated(totalValue, fee, surplus);

        // close the cdp
        tub.shut(_cup);
        emit Shut();

        // transfer the surplus
        tub.skr().transfer(msg.sender, rdiv(surplus, price));
        emit Transfered();
    }

    // Receives DAI
    function fund(uint amount) public {
        require(amount > 0);

        // transfer dai to contract
        require(dai.transferFrom(msg.sender, address(this), amount));

        balances[msg.sender] += amount;
        raised += amount;

        emit Funded(msg.sender, amount, balances[msg.sender]);
    }

    // Get all the DAI out
    function pull() public {
        // calculate premium
        uint funded = balances[msg.sender];
        balances[msg.sender] = 0;

        require(funded > 0);

        // how much this sender has funded, in percent
        uint percentage = wdiv(funded, raised);

        // percentage of the fee the caller gets
        uint feeInPeth = rdiv(fee, price);
        uint payout = wmul(percentage, feeInPeth);

        // refund dai
        require(dai.transfer(msg.sender, funded));
        // reward eth
        require(tub.skr().transfer(msg.sender, payout));

        emit Paid(msg.sender, payout);
    }
}
