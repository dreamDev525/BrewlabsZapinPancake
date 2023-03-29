// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./oz/access/Ownable.sol";
import "./oz/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function deposit() external payable;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IUniswapV2Pair {
    function token0() external pure returns (address);

    function token1() external pure returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        );
}

interface IBrewlabsLiquidityManager {
    function addLiquidity(
        address token0,
        address token1,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _slipPage
    )
        external
        payable
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidityETH(address token, uint256 _amount)
        external
        returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidity(
        address token0,
        address token1,
        uint256 _amount
    ) external returns (uint256 amountA, uint256 amountB);
}

interface IMasterChefV2 {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pendingCake(uint256 _pid, address _user)
        external
        view
        returns (uint256);
}

library Babylonian {
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0
    }
}

contract BrewlabsZapInPancakeV2 is Ownable {
    using SafeERC20 for IERC20;

    IUniswapV2Factory private constant pancakeswapFactory =
        IUniswapV2Factory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);

    IUniswapV2Router02 private constant pancakeswapRouter =
        IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    IBrewlabsLiquidityManager private constant brewlabsLiquidityManager =
        IBrewlabsLiquidityManager(0x49dcF1d27556A818105bbB349DD2daC7A95c3F16);

    IMasterChefV2 private constant masterChefV2 =
        IMasterChefV2(0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652);

    IERC20 private constant cake =
        IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);

    address private constant wbnbTokenAddress =
        0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address private constant brewlabsAddress =
        0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7;

    address internal constant ETHAddress =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 private constant deadline =
        0xf000000000000000000000000000000000000000000000000000000000000000;

    uint256 public feeAmount;
    address payable public feeAddress;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 totalRewards;
    }

    struct PoolInfo {
        uint256 accCakePerShare;
        uint256 lastRewardBlock;
        uint256 totalBoostedShare;
        uint256 totalRewards;
    }

    mapping(uint256 => PoolInfo) public poolInfo;
    mapping(uint256 => address) public lpToken;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public constant ACC_CAKE_PRECISION = 1e18;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateFeeAmount(uint256 indexed oldAmount, uint256 indexed newAmount);
    event UpdateFeeAddress(
        address indexed oldAddress,
        address indexed newAddress
    );

    constructor(uint256 _feeAmount, address payable _feeAddress) {
        feeAmount = _feeAmount;
        feeAddress = _feeAddress;
    }

    receive() external payable {
        require(msg.sender != tx.origin, "Do not send ETH directly");
    }

    function updateFeeAmount(uint256 _newAmount) external onlyOwner {
        require(
            _newAmount != feeAmount,
            "Brewlabs: Cannot update to same value"
        );
        uint256 _oldAmount = feeAmount;
        feeAmount = _newAmount;
        emit UpdateFeeAmount(_oldAmount, _newAmount);
    }

    function updateFeeAddress(address payable _newAddress) external onlyOwner {
        require(
            _newAddress != feeAddress,
            "Brewlabs: Cannot update to same value"
        );
        address _oldAddress = feeAddress;
        feeAddress = _newAddress;
        emit UpdateFeeAddress(_oldAddress, _newAddress);
    }

    function withdrawTokens(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == ETHAddress) {
                Address.sendValue(payable(owner()), address(this).balance);
            } else {
                IERC20(tokens[i]).safeTransfer(
                    owner(),
                    IERC20(tokens[i]).balanceOf(address(this))
                );
            }
        }
    }

    function zapIn(
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _pid,
        uint256 _amount,
        uint256 _minPoolTokens,
        address _rewardAddress
    ) external payable {
        if (isETH(_FromTokenContractAddress)) {
            require(
                msg.value >= _amount + feeAmount,
                "Brewlabs: Eth is not enough"
            );
        } else {
            require(msg.value >= feeAmount, "Brewlabs: Eth is not enough");
        }
        feeAddress.transfer(feeAmount);

        uint256 LPBought = _performZapIn(
            _FromTokenContractAddress,
            _pairAddress,
            _amount
        );
        require(LPBought >= _minPoolTokens, "Brewlabs: High Slippage");

        if (lpToken[_pid] == address(0)) lpToken[_pid] = _pairAddress;
        deposit(_pid, LPBought, _rewardAddress);

        emit Deposit(msg.sender, _pid, LPBought);
    }

    function zapOut(
        uint256 _pid,
        uint256 _amount,
        address _reward
    ) external payable {
        require(msg.value >= feeAmount, "Brewlabs: Eth is not enough");
        feeAddress.transfer(feeAmount);

        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "Brewlabs: Insufficient for withdraw");

        masterChefV2.withdraw(_pid, _amount);

        settlePendingCake(msg.sender, _pid, _reward);

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            withdraw(_pid, _amount);
        }

        user.rewardDebt =
            (user.amount * pool.accCakePerShare) /
            ACC_CAKE_PRECISION;
        poolInfo[_pid].totalBoostedShare =
            poolInfo[_pid].totalBoostedShare -
            _amount;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    function pendingCake(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accCakePerShare = pool.accCakePerShare;
        uint256 lpSupply = pool.totalBoostedShare;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 cakeReward = masterChefV2.pendingCake(_pid, address(this));
            accCakePerShare =
                accCakePerShare +
                (cakeReward * ACC_CAKE_PRECISION) /
                lpSupply;
        }
        return
            (user.amount * accCakePerShare) /
            ACC_CAKE_PRECISION -
            user.rewardDebt;
    }

    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _reward
    ) internal {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (_amount > 0)
            _approveToken(lpToken[_pid], address(masterChefV2), _amount);

        masterChefV2.deposit(_pid, _amount);

        if (user.amount > 0) {
            settlePendingCake(msg.sender, _pid, _reward);
        }

        if (_amount > 0) {
            user.amount = user.amount + _amount;
            poolInfo[_pid].totalBoostedShare =
                poolInfo[_pid].totalBoostedShare +
                _amount;
        }

        user.rewardDebt =
            (user.amount * pool.accCakePerShare) /
            ACC_CAKE_PRECISION;
    }

    function withdraw(uint256 _pid, uint256 _amount) internal {
        IUniswapV2Pair pair = IUniswapV2Pair(lpToken[_pid]);

        address token0 = pair.token0();
        address token1 = pair.token1();

        _approveToken(
            lpToken[_pid],
            address(brewlabsLiquidityManager),
            _amount
        );

        if (token0 == wbnbTokenAddress || token1 == wbnbTokenAddress) {
            address _token = token0 == wbnbTokenAddress ? token1 : token0;

            (uint256 amountToken, uint256 amountETH) = brewlabsLiquidityManager
                .removeLiquidityETH(_token, _amount);

            uint256 amountTrade = _token2ETH(_token, amountToken);

            payable(msg.sender).transfer(amountETH + amountTrade);
        } else {
            (uint256 amountA, uint256 amountB) = brewlabsLiquidityManager
                .removeLiquidity(token0, token1, _amount);

            uint256 amountETH0 = _token2ETH(token0, amountA);
            uint256 amountETH1 = _token2ETH(token1, amountB);

            payable(msg.sender).transfer(amountETH0 + amountETH1);
        }
    }

    function updatePool(uint256 _pid) internal returns (PoolInfo memory pool) {
        pool = poolInfo[_pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = pool.totalBoostedShare;

            if (lpSupply > 0) {
                uint256 cakeReward = masterChefV2.pendingCake(
                    _pid,
                    address(this)
                );
                pool.accCakePerShare =
                    pool.accCakePerShare +
                    ((cakeReward * ACC_CAKE_PRECISION) / lpSupply);
            }
            pool.lastRewardBlock = block.number;
            poolInfo[_pid] = pool;
        }
    }

    function settlePendingCake(
        address _user,
        uint256 _pid,
        address _reward
    ) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accCake = (user.amount * (poolInfo[_pid].accCakePerShare)) /
            ACC_CAKE_PRECISION;
        uint256 pending = accCake - user.rewardDebt;

        user.totalRewards = user.totalRewards + pending;
        pool.totalRewards = pool.totalRewards + pending;

        if (_reward == address(cake)) {
            cake.safeTransfer(_user, pending);
        } else if (_reward == lpToken[_pid]) {
            // swap cake rewards to eth
            uint amountETH = _token2ETH(address(cake), pending);

            // invest the eth to buy LP
            uint256 _amount = _performZapIn(
                ETHAddress,
                lpToken[_pid],
                amountETH
            );

            // deposit to masterChef manually
            _approveToken(lpToken[_pid], address(masterChefV2), _amount);
            masterChefV2.deposit(_pid, _amount);

            // update user and pool info
            user.amount = user.amount + _amount;
            pool.totalBoostedShare = pool.totalBoostedShare + _amount;
        } else {
            // swap cake to reward token
            uint256 beforeAmt = IERC20(_reward).balanceOf(address(this));
            _token2Token(address(cake), _reward, pending);
            uint256 afterAmt = IERC20(_reward).balanceOf(address(this));

            IERC20(_reward).safeTransfer(_user, afterAmt - beforeAmt);
        }
    }

    function _performZapIn(
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _amount
    ) internal returns (uint256) {
        uint256 intermediateAmt;
        address intermediateToken;
        (address _ToUniswapToken0, address _ToUniswapToken1) = _getPairTokens(
            _pairAddress
        );

        if (isETH(_FromTokenContractAddress)) {
            IWETH(wbnbTokenAddress).deposit{value: _amount}();
            intermediateToken = wbnbTokenAddress;
            intermediateAmt = _amount;
        } else {
            IERC20(_FromTokenContractAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            if (
                _ToUniswapToken0 == _FromTokenContractAddress ||
                _ToUniswapToken1 == _FromTokenContractAddress
            ) {
                intermediateToken = _FromTokenContractAddress;
                intermediateAmt = _amount;
            } else {
                intermediateToken = wbnbTokenAddress;
                intermediateAmt = _token2Token(
                    _FromTokenContractAddress,
                    wbnbTokenAddress,
                    _amount
                );
            }
        }

        (uint256 token0Bought, uint256 token1Bought) = _swapIntermediate(
            intermediateToken,
            _ToUniswapToken0,
            _ToUniswapToken1,
            intermediateAmt
        );

        return
            _uniDeposit(
                _ToUniswapToken0,
                _ToUniswapToken1,
                token0Bought,
                token1Bought
            );
    }

    function _uniDeposit(
        address _ToUnipoolToken0,
        address _ToUnipoolToken1,
        uint256 token0Bought,
        uint256 token1Bought
    ) internal returns (uint256) {
        _approveToken(
            _ToUnipoolToken0,
            address(brewlabsLiquidityManager),
            token0Bought
        );
        _approveToken(
            _ToUnipoolToken1,
            address(brewlabsLiquidityManager),
            token1Bought
        );

        (, , uint256 LP) = brewlabsLiquidityManager.addLiquidity(
            _ToUnipoolToken0,
            _ToUnipoolToken1,
            token0Bought,
            token1Bought,
            9999
        );
        return LP;
    }

    function _swapIntermediate(
        address _toContractAddress,
        address _ToUnipoolToken0,
        address _ToUnipoolToken1,
        uint256 _amount
    ) internal returns (uint256 token0Bought, uint256 token1Bought) {
        IUniswapV2Pair pair = IUniswapV2Pair(
            pancakeswapFactory.getPair(_ToUnipoolToken0, _ToUnipoolToken1)
        );
        (uint256 res0, uint256 res1, ) = pair.getReserves();
        if (_toContractAddress == _ToUnipoolToken0) {
            uint256 amountToSwap = calculateSwapInAmount(res0, _amount);
            if (amountToSwap <= 0) amountToSwap = _amount / 2;
            token1Bought = _token2Token(
                _toContractAddress,
                _ToUnipoolToken1,
                amountToSwap
            );
            token0Bought = _amount - amountToSwap;
        } else if (_toContractAddress == _ToUnipoolToken1) {
            uint256 amountToSwap = calculateSwapInAmount(res1, _amount);
            if (amountToSwap <= 0) amountToSwap = _amount / 2;
            token0Bought = _token2Token(
                _toContractAddress,
                _ToUnipoolToken0,
                amountToSwap
            );
            token1Bought = _amount - amountToSwap;
        } else {
            uint256 amountToSwap = _amount / 2;
            token0Bought = _token2Token(
                _toContractAddress,
                _ToUnipoolToken0,
                amountToSwap
            );
            token1Bought = _token2Token(
                _toContractAddress,
                _ToUnipoolToken1,
                _amount - amountToSwap
            );
        }
    }

    function _token2Token(
        address _FromTokenContractAddress,
        address _ToTokenContractAddress,
        uint256 tokens2Trade
    ) internal returns (uint256 tokenBought) {
        if (_FromTokenContractAddress == _ToTokenContractAddress) {
            return tokens2Trade;
        }

        _approveToken(
            _FromTokenContractAddress,
            address(pancakeswapRouter),
            tokens2Trade
        );

        if (_ToTokenContractAddress == brewlabsAddress) {
            address[] memory path = new address[](3);

            path[0] = _FromTokenContractAddress;
            path[1] = wbnbTokenAddress;
            path[2] = _ToTokenContractAddress;

            tokenBought = pancakeswapRouter.swapExactTokensForTokens(
                tokens2Trade,
                1,
                path,
                address(this),
                deadline
            )[path.length - 1];
        } else {
            address[] memory path = new address[](2);

            path[0] = _FromTokenContractAddress;
            path[1] = _ToTokenContractAddress;

            tokenBought = pancakeswapRouter.swapExactTokensForTokens(
                tokens2Trade,
                1,
                path,
                address(this),
                deadline
            )[path.length - 1];
        }
    }

    function _token2ETH(address _FromTokenContractAddress, uint256 tokens2Trade)
        internal
        returns (uint256 amountETH)
    {
        _approveToken(
            _FromTokenContractAddress,
            address(pancakeswapRouter),
            tokens2Trade
        );

        address[] memory path = new address[](2);
        path[0] = _FromTokenContractAddress;
        path[1] = wbnbTokenAddress;

        amountETH = pancakeswapRouter.swapExactTokensForETH(
            tokens2Trade,
            1,
            path,
            address(this),
            deadline
        )[path.length - 1];
    }

    function _approveToken(address token, address spender) internal {
        IERC20 _token = IERC20(token);
        if (_token.allowance(address(this), spender) > 0) return;
        else {
            _token.safeApprove(spender, type(uint256).max);
        }
    }

    function _approveToken(
        address token,
        address spender,
        uint256 amount
    ) internal {
        IERC20(token).safeApprove(spender, 0);
        IERC20(token).safeApprove(spender, amount);
    }

    function _getPairTokens(address _pairAddress)
        internal
        pure
        returns (address token0, address token1)
    {
        IUniswapV2Pair uniPair = IUniswapV2Pair(_pairAddress);
        token0 = uniPair.token0();
        token1 = uniPair.token1();
    }

    function calculateSwapInAmount(uint256 reserveIn, uint256 userIn)
        internal
        pure
        returns (uint256)
    {
        return
            (Babylonian.sqrt(
                reserveIn * ((userIn * 3988000) + (reserveIn * 3988009))
            ) - (reserveIn * 1997)) / 1994;
    }

    function isETH(address token) internal pure returns (bool) {
        return (token == ETHAddress || token == address(0));
    }
}
