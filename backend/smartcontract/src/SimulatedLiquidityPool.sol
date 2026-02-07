// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./IERC20.sol";

contract SimulatedLiquidityPool {
    /// @notice Underlying asset (USDC on Base Sepolia for the demo).
    IERC20 public immutable asset;

    uint256 public lastAccrual;
    uint256 public immutable annualRateBps; // e.g. 500 = 5%

    /// @notice Exchange rate: underlying per share (WAD-scaled).
    uint256 public index = 1e18; // 1.0

    mapping(address => uint256) public sharesOf;
    uint256 public totalShares;

    uint256 private constant BPS = 10_000;
    uint256 private constant YEAR = 365 days;
    uint256 private constant WAD = 1e18;

    event YieldFunded(address indexed from, uint256 amount);
    event InterestAccrued(uint256 elapsed, uint256 interestApplied, uint256 newIndex);
    event Deposited(address indexed account, uint256 amount, uint256 sharesMinted);
    event Withdrawn(address indexed account, uint256 amount, uint256 sharesBurned);

    constructor(address _asset, uint256 _annualRateBps) {
        require(_asset != address(0), "bad asset");
        require(_annualRateBps <= BPS, "rate too high"); // demo safety guard (<= 100% APR)
        asset = IERC20(_asset);
        annualRateBps = _annualRateBps;
        lastAccrual = block.timestamp;
    }

    /// @dev Total underlying owed to LPs based on shares and index.
    function _totalUnderlying() internal view returns (uint256) {
        // total underlying = totalShares * index
        return (totalShares * index) / WAD;
    }

    /// @notice Excess underlying sitting in the pool that can be used as "yield reserve".
    /// If someone sends extra USDC to this contract (via fundYield or direct transfer),
    /// accrueInterest can "materialize" it into the index.
    function yieldReserve() public view returns (uint256) {
        uint256 bal = asset.balanceOf(address(this));
        uint256 owed = _totalUnderlying();
        if (bal <= owed) return 0;
        return bal - owed;
    }

    /// @notice Fund the pool with extra underlying to simulate yield (no shares minted).
    /// Anyone can call this (useful for demos).
    function fundYield(uint256 amount) external {
        require(amount > 0, "amount=0");
        require(asset.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        emit YieldFunded(msg.sender, amount);
    }

    /// @notice Accrues interest by increasing the index, limited by available yield reserve.
    /// @dev With real USDC, we cannot mint. So yield must come from pre-funded reserve.
    function accrueInterest() public {
        if (totalShares == 0) {
            lastAccrual = block.timestamp;
            return;
        }

        uint256 elapsed = block.timestamp - lastAccrual;
        if (elapsed == 0) return;

        uint256 underlyingBefore = _totalUnderlying();

        // interestWanted = underlying * rate * time
        uint256 interestWanted =
            (underlyingBefore * annualRateBps * elapsed) /
            (BPS * YEAR);

        // Cap by what the pool can actually pay (yield reserve).
        uint256 reserve = yieldReserve();
        uint256 interestApplied = interestWanted;
        if (interestApplied > reserve) {
            interestApplied = reserve;
        }

        if (interestApplied > 0) {
            uint256 underlyingAfter = underlyingBefore + interestApplied;
            index = (underlyingAfter * WAD) / totalShares;
        }

        lastAccrual = block.timestamp;
        emit InterestAccrued(elapsed, interestApplied, index);
    }

    /// @notice Underlying balance for an account (based on shares and index).
    function balances(address account) external view returns (uint256) {
        return (sharesOf[account] * index) / WAD;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "amount=0");
        accrueInterest();

        require(asset.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        uint256 mintedShares = (amount * WAD) / index;
        require(mintedShares > 0, "mintedShares=0");

        sharesOf[msg.sender] += mintedShares;
        totalShares += mintedShares;

        emit Deposited(msg.sender, amount, mintedShares);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "amount=0");
        accrueInterest();

        uint256 sharesToBurn = (amount * WAD) / index;
        if ((sharesToBurn * index) / WAD < amount) sharesToBurn += 1;

        require(sharesOf[msg.sender] >= sharesToBurn, "insufficient");
        sharesOf[msg.sender] -= sharesToBurn;
        totalShares -= sharesToBurn;

        require(asset.transfer(msg.sender, amount), "transfer failed");

        emit Withdrawn(msg.sender, amount, sharesToBurn);
    }
}

