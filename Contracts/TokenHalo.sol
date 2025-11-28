// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title TokenHalo
 * @notice ERC20 token with transfer-fee reward pool ("halo") and staking rewards.
 * @dev Transfer fee is collected to the contract and distributed to stakers.
 */

contract TokenHalo {
    // ERC20 basic state
    string public name = "TokenHalo";
    string public symbol = "HALO";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    // Ownership
    address public owner;

    // Balances & allowances
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Transfer fee (in basis points: parts per 10,000). e.g. 100 = 1%
    uint16 public transferFeeBP = 200; // default 2.00%
    uint16 public constant MAX_FEE_BP = 1000; // max 10%

    // Fee-exempt addresses
    mapping(address => bool) public isFeeExempt;

    // Staking / Rewards accounting
    uint256 public totalStaked;
    mapping(address => uint256) public stakedBalance;

    // Reward distribution using reward per token stored (scaled)
    uint256 public rewardPerTokenStored; // scaled by 1e18
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards; // accrued rewards for user

    // Scaling factor for precision
    uint256 private constant SCALE = 1e18;

    // Reentrancy guard
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);
    event TransferFeeUpdated(uint16 oldFeeBP, uint16 newFeeBP);
    event FeeExemptUpdated(address indexed account, bool exempt);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "TokenHalo: not owner");
        _;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "TokenHalo: reentrant");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor(uint256 initialSupply) {
        owner = msg.sender;
        _status = _NOT_ENTERED;
        _mint(msg.sender, initialSupply);
        // contract and owner exempt by default
        isFeeExempt[address(this)] = true;
        isFeeExempt[owner] = true;
    }

    // ---------------- ERC20 ----------------

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "TokenHalo: allowance exceeded");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    // ---------------- Internal transfer & fee ----------------

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "TokenHalo: zero address");
        require(balanceOf[from] >= amount, "TokenHalo: insufficient balance");

        // Update rewards state for from & to before balances change
        _updateReward(from);
        _updateReward(to);

        uint256 feeAmount = 0;
        if (!isFeeExempt[from] && !isFeeExempt[to] && transferFeeBP > 0) {
            feeAmount = (amount * transferFeeBP) / 10000;
        }

        uint256 sendAmount = amount - feeAmount;

        // Transfer
        balanceOf[from] -= amount;
        balanceOf[to] += sendAmount;
        emit Transfer(from, to, sendAmount);

        // Handle fee: add to contract balance (reward pool) and increase rewardPerTokenStored if there are stakers
        if (feeAmount > 0) {
            balanceOf[address(this)] += feeAmount;
            emit Transfer(from, address(this), feeAmount);

            if (totalStaked > 0) {
                // distribute fee to stakers by increasing rewardPerTokenStored
                // scaled: feeAmount * SCALE / totalStaked
                uint256 increment = (feeAmount * SCALE) / totalStaked;
                rewardPerTokenStored += increment;
            } // if no stakers, fee remains in contract until stakers exist or owner withdraws/mints
        }
    }

    // ---------------- Staking / Rewards ----------------

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "TokenHalo: amount 0");
        require(balanceOf[msg.sender] >= amount, "TokenHalo: insufficient balance");

        _updateReward(msg.sender);

        // move tokens into staking (they remain recorded in contract balance)
        balanceOf[msg.sender] -= amount;
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;

        // ensure contract holds staked tokens: increase contract balance
        balanceOf[address(this)] += amount;
        emit Transfer(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "TokenHalo: amount 0");
        require(stakedBalance[msg.sender] >= amount, "TokenHalo: not enough staked");

        _updateReward(msg.sender);

        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        // transfer tokens back from contract to user
        require(balanceOf[address(this)] >= amount, "TokenHalo: contract balance insufficient");
        balanceOf[address(this)] -= amount;
        balanceOf[msg.sender] += amount;
        emit Transfer(address(this), msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() external nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "TokenHalo: no rewards");

        rewards[msg.sender] = 0;

        // Ensure contract balance has rewards (fees accumulate here)
        require(balanceOf[address(this)] >= reward, "TokenHalo: insufficient contract balance");
        balanceOf[address(this)] -= reward;
        balanceOf[msg.sender] += reward;
        emit Transfer(address(this), msg.sender, reward);

        emit RewardPaid(msg.sender, reward);
    }

    // Internal: update reward accounting for an account
    function _updateReward(address account) internal {
        if (totalStaked > 0) {
            // rewardPerTokenStored already updated on each fee; nothing to do extra here
        }
        if (account != address(0)) {
            // compute earned = stakedBalance * (rewardPerTokenStored - userPaid) / SCALE
            uint256 paid = userRewardPerTokenPaid[account];
            uint256 delta = 0;
            if (rewardPerTokenStored > paid && stakedBalance[account] > 0) {
                delta = (stakedBalance[account] * (rewardPerTokenStored - paid)) / SCALE;
                rewards[account] += delta;
            }
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    // View: earned rewards for a user (does not modify state)
    function earned(address account) public view returns (uint256) {
        uint256 paid = userRewardPerTokenPaid[account];
        uint256 delta = 0;
        if (rewardPerTokenStored > paid && stakedBalance[account] > 0) {
            delta = (stakedBalance[account] * (rewardPerTokenStored - paid)) / SCALE;
        }
        return rewards[account] + delta;
    }

    // ---------------- Admin / Config ----------------

    function setTransferFeeBP(uint16 newFeeBP) external onlyOwner {
        require(newFeeBP <= MAX_FEE_BP, "TokenHalo: fee too high");
        uint16 old = transferFeeBP;
        transferFeeBP = newFeeBP;
        emit TransferFeeUpdated(old, newFeeBP);
    }

    function setFeeExempt(address account, bool exempt) external onlyOwner {
        isFeeExempt[account] = exempt;
        emit FeeExemptUpdated(account, exempt);
    }

    // Owner mint / burn (useful for initial supply and future policy)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    // Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "TokenHalo: zero owner");
        address old = owner;
        owner = newOwner;
        // ensure new owner exempt by default
        isFeeExempt[newOwner] = true;
        emit OwnershipTransferred(old, newOwner);
    }

    // ---------------- Internal mint / burn ----------------

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "TokenHalo: mint to zero");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "TokenHalo: burn from zero");
        require(balanceOf[from] >= amount, "TokenHalo: burn exceeds balance");

        // If burning staked tokens, prevent inconsistency
        require(stakedBalance[from] == 0, "TokenHalo: cannot burn while staked");

        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
        emit Burn(from, amount);
    }

    // ---------------- Convenience ----------------

    // Rescue tokens accidentally sent to contract (only owner)
    function rescueERC20(address tokenAddress, address to, uint256 amount) external onlyOwner {
        require(tokenAddress != address(this), "TokenHalo: cannot rescue HALO");
        // ERC20 transfer out: use low-level call to support non-standard tokens
        (bool success, bytes memory data) = tokenAddress.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TokenHalo: rescue failed");
    }

    // Allow renouncing ownership (owner should be careful)
    function renounceOwnership() external onlyOwner {
        address old = owner;
        owner = address(0);
        emit OwnershipTransferred(old, address(0));
    }
}
