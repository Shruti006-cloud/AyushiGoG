// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TokenHalo
 * @dev A reputation-based token reward system that creates a "halo" effect around high-performing users
 * @notice This contract allows users to earn reputation points and claim token rewards based on their activity
 */
contract TokenHalo {
    
    // State variables
    address public owner;
    uint256 public totalReputationPoints;
    uint256 public rewardPool;
    uint256 public constant REPUTATION_TO_TOKEN_RATIO = 10; // 1 token per 10 reputation points
    
    // Structs
    struct UserProfile {
        uint256 reputationScore;
        uint256 totalRewardsClaimed;
        uint256 lastActivityTimestamp;
        bool isActive;
    }
    
    // Mappings
    mapping(address => UserProfile) public userProfiles;
    mapping(address => bool) public authorizedRewarders;
    
    // Events
    event ReputationAwarded(address indexed user, uint256 points, uint256 newTotal);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardPoolFunded(address indexed funder, uint256 amount);
    event RewarderAuthorized(address indexed rewarder, bool status);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyAuthorizedRewarder() {
        require(authorizedRewarders[msg.sender] || msg.sender == owner, "Not authorized to award reputation");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        authorizedRewarders[msg.sender] = true;
    }
    
    /**
     * @dev Core Function 1: Award reputation points to a user
     * @param user Address of the user receiving reputation
     * @param points Number of reputation points to award
     */
    function awardReputation(address user, uint256 points) external onlyAuthorizedRewarder {
        require(user != address(0), "Invalid user address");
        require(points > 0, "Points must be greater than zero");
        
        UserProfile storage profile = userProfiles[user];
        
        if (!profile.isActive) {
            profile.isActive = true;
        }
        
        profile.reputationScore += points;
        profile.lastActivityTimestamp = block.timestamp;
        totalReputationPoints += points;
        
        emit ReputationAwarded(user, points, profile.reputationScore);
    }
    
    /**
     * @dev Core Function 2: Claim token rewards based on reputation
     * @notice Users can convert their reputation points to token rewards
     */
    function claimRewards() external {
        UserProfile storage profile = userProfiles[msg.sender];
        require(profile.isActive, "User profile not active");
        require(profile.reputationScore > 0, "No reputation points to claim");
        
        uint256 rewardAmount = profile.reputationScore / REPUTATION_TO_TOKEN_RATIO;
        require(rewardAmount > 0, "Insufficient reputation for minimum reward");
        require(rewardPool >= rewardAmount, "Insufficient reward pool balance");
        
        // Calculate actual reputation points to deduct
        uint256 reputationUsed = rewardAmount * REPUTATION_TO_TOKEN_RATIO;
        
        profile.reputationScore -= reputationUsed;
        profile.totalRewardsClaimed += rewardAmount;
        rewardPool -= rewardAmount;
        
        // Transfer rewards (in wei)
        payable(msg.sender).transfer(rewardAmount);
        
        emit RewardClaimed(msg.sender, rewardAmount);
    }
    
    /**
     * @dev Core Function 3: Get user's halo status and statistics
     * @param user Address of the user to query
     * @return reputationScore Current reputation score
     * @return totalClaimed Total rewards claimed
     * @return claimableRewards Currently claimable reward amount
     * @return haloLevel User's tier level based on reputation
     */
    function getUserHaloStatus(address user) external view returns (
        uint256 reputationScore,
        uint256 totalClaimed,
        uint256 claimableRewards,
        string memory haloLevel
    ) {
        UserProfile memory profile = userProfiles[user];
        reputationScore = profile.reputationScore;
        totalClaimed = profile.totalRewardsClaimed;
        claimableRewards = reputationScore / REPUTATION_TO_TOKEN_RATIO;
        
        // Determine halo level based on reputation
        if (reputationScore >= 1000) {
            haloLevel = "Diamond Halo";
        } else if (reputationScore >= 500) {
            haloLevel = "Gold Halo";
        } else if (reputationScore >= 100) {
            haloLevel = "Silver Halo";
        } else if (reputationScore > 0) {
            haloLevel = "Bronze Halo";
        } else {
            haloLevel = "No Halo";
        }
        
        return (reputationScore, totalClaimed, claimableRewards, haloLevel);
    }
    
    // Admin functions
    function fundRewardPool() external payable {
        require(msg.value > 0, "Must send ETH to fund pool");
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.sender, msg.value);
    }
    
    function authorizeRewarder(address rewarder, bool status) external onlyOwner {
        authorizedRewarders[rewarder] = status;
        emit RewarderAuthorized(rewarder, status);
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    receive() external payable {
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.sender, msg.value);
    }
}
