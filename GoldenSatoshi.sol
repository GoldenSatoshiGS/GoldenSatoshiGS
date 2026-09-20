// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Golden Satoshi (GS) - v2
/// @notice BEP20-like token with:
// - 5% founder allocation minted to founderAddress
// - sell-only taxes: < 10,000 GS => 2% -> devWallet
//                    >=10,000 GS => 15% -> liquidityWallet
// - 0% buy tax (detected when sender == pairAddress)
// - owner can set pairAddress, wallets, exclusions
contract GoldenSatoshi {
    string public name = "Golden Satoshi";
    string public symbol = "GS";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public owner;

    // wallets
    address public founderAddress = 0x704266C53fe703ddF60dd198Bdf412C0d2905445;
    address public devWallet      = 0x9CDEE14FCEf76162c5d7F699c819e4107F1b3fd6; // development
    address public liquidityWallet= 0xe2b39546475134Dd60550DaC779aCCB6DF8bC413; // liquidity

    // Pair contract address (set this after creating LP on PancakeSwap)
    address public pairAddress;

    // tax settings (fixed percentages as per spec)
    uint256 public smallSellTaxPercent = 2;   // < threshold -> to devWallet
    uint256 public largeSellTaxPercent = 15;  // >= threshold -> to liquidityWallet

    // threshold in token units (without decimals). here 10,000 tokens.
    uint256 public sellThresholdTokens = 10000;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // exclusions
    mapping(address => bool) public isExcludedFromTax;
    mapping(address => bool) public isExcludedFromLimits; // not used heavily here, placeholder

    // events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed ownerAddr, address indexed spender, uint256 value);
    event OwnerTransferred(address indexed previousOwner, address indexed newOwner);
    event PairAddressSet(address indexed pair);
    event DevWalletSet(address indexed dev);
    event LiquidityWalletSet(address indexed liq);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        owner = msg.sender;

        uint256 factor = 10 ** uint256(decimals);
        totalSupply = 21000000 * factor; // 21,000,000 * 10^18

        // 5% to founderAddress
        uint256 founderAmount = (totalSupply * 5) / 100; // 1,050,000 * 10^18
        balanceOf[founderAddress] = founderAmount;
        emit Transfer(address(0), founderAddress, founderAmount);

        // remaining -> deployer (owner)
        uint256 remaining = totalSupply - founderAmount;
        balanceOf[owner] = remaining;
        emit Transfer(address(0), owner, remaining);

        // default exclusions: contract itself, owner, founder, dev, liquidity
        isExcludedFromTax[address(this)] = true;
        isExcludedFromTax[owner] = true;
        isExcludedFromTax[founderAddress] = true;
        isExcludedFromTax[devWallet] = true;
        isExcludedFromTax[liquidityWallet] = true;
    }

    // ERC20-like
    function approve(address _spender, uint256 _value) external returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function transfer(address _to, uint256 _value) external returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
        uint256 currentAllowance = allowance[_from][msg.sender];
        require(currentAllowance >= _value, "Allowance too low");
        allowance[_from][msg.sender] = currentAllowance - _value;
        _transfer(_from, _to, _value);
        return true;
    }

    // Internal transfer logic with sell-only tax
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(balanceOf[sender] >= amount, "Insufficient balance");

        // If either excluded from tax -> simple transfer
        if (isExcludedFromTax[sender] || isExcludedFromTax[recipient]) {
            balanceOf[sender] -= amount;
            balanceOf[recipient] += amount;
            emit Transfer(sender, recipient, amount);
            return;
        }

        // Detect BUY vs SELL:
        if (sender == pairAddress) {
            // buy: no tax
            balanceOf[sender] -= amount;
            balanceOf[recipient] += amount;
            emit Transfer(sender, recipient, amount);
            return;
        } else if (recipient == pairAddress) {
            // sell: apply tiered tax based on raw token amount threshold (token units)
            uint256 thresholdWithDecimals = sellThresholdTokens * (10 ** uint256(decimals));
            if (amount < thresholdWithDecimals) {
                // small sell -> smallSellTaxPercent -> devWallet
                uint256 tax = (amount * smallSellTaxPercent) / 100;
                uint256 net = amount - tax;
                balanceOf[sender] -= amount;
                balanceOf[devWallet] += tax;
                balanceOf[recipient] += net;
                emit Transfer(sender, devWallet, tax);
                emit Transfer(sender, recipient, net);
                return;
            } else {
                // large sell -> largeSellTaxPercent -> liquidityWallet
                uint256 tax = (amount * largeSellTaxPercent) / 100;
                uint256 net = amount - tax;
                balanceOf[sender] -= amount;
                balanceOf[liquidityWallet] += tax;
                balanceOf[recipient] += net;
                emit Transfer(sender, liquidityWallet, tax);
                emit Transfer(sender, recipient, net);
                return;
            }
        } else {
            // wallet-to-wallet transfer (not buy/sell) -> no tax
            balanceOf[sender] -= amount;
            balanceOf[recipient] += amount;
            emit Transfer(sender, recipient, amount);
            return;
        }
    }

    // Owner functions to update addresses and settings
    function setPairAddress(address _pair) external onlyOwner {
        pairAddress = _pair;
        emit PairAddressSet(_pair);
    }

    function setDevWallet(address _dev) external onlyOwner {
        devWallet = _dev;
        emit DevWalletSet(_dev);
    }

    function setLiquidityWallet(address _liq) external onlyOwner {
        liquidityWallet = _liq;
        emit LiquidityWalletSet(_liq);
    }

    function setSellThresholdTokens(uint256 _tokens) external onlyOwner {
        require(_tokens > 0, "must be >0");
        sellThresholdTokens = _tokens;
    }

    function setExcludedFromTax(address _acct, bool _val) external onlyOwner {
        isExcludedFromTax[_acct] = _val;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }
}