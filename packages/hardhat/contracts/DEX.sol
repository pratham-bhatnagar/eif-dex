// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this branch/repo. Also return variable names that may need to be specified exactly may be referenced (if you are confused, see solutions folder in this repo and/or cross reference with front-end code).
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    using SafeMath for uint256; //outlines use of SafeMath for uint256 variables
    IERC20 token; //instantiates the imported contract

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(
        address swapper,
        string txDetails,
        uint256 ethInput,
        uint256 tokenOutput
    );

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(
        address swapper,
        string txDetails,
        uint256 tokensInput,
        uint256 ethOutput
    );

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(
        address liquidityProvider,
        uint256 tokensInput,
        uint256 ethInput,
        uint256 liquidityMinted
    );

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(
        address liquidityRemover,
        uint256 tokensOutput,
        uint256 ethOutput,
        uint256 liquidityWithdrawn
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     * @param tokens amount to be transferred to DEX
     * @return totalLiquidity is the number of LPTs minting as a result of deposits made to DEX contract
     * NOTE: since ratio is 1:1, this is fine to initialize the totalLiquidity (wrt to balloons) as equal to eth balance of contract.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "DEX-already has liquidity");
        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;
        require(
            token.transferFrom(msg.sender, address(this), tokens),
            "Tokens not sent!"
        );
        return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     * @dev Follow along with the [original tutorial](https://medium.com/@austin_48503/%EF%B8%8F-minimum-viable-exchange-d84f30bd0c90) Price section for an understanding of the DEX's pricing model and for a price function to add to your contract. You may need to update the Solidity syntax (e.g. use + instead of .add, * instead of .mul, etc). Deploy when you are done.
     */
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public view returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput.mul(997);
        uint256 numerator = xInputWithFee.mul(yReserves);
        uint256 denominator = (xReserves.mul(1000)).add(xInputWithFee);
        return (numerator / denominator);
    }

    // dy = y * 0.997 * dx / (x+0.997 * dx)

    /**
     * @notice returns liquidity for a user. Note this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     * if you are using a mapping liquidity, then you can use `return liquidity[lp]` to get the liquidity for a user.
     *
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(
            msg.value > 0,
            "DEX-ethToToken: msg.value must be greater than 0"
        );
        uint256 ethReserve = address(this).balance.sub(msg.value);
        uint256 token_reserve = token.balanceOf(address(this));
        tokenOutput = price(msg.value, ethReserve, token_reserve);
        require(token.transfer(msg.sender, tokenOutput), "Tokens not sent!");
        emit EthToTokenSwap(
            msg.sender,
            "ETH to token swap",
            msg.value,
            tokenOutput
        );
        return tokenOutput;
    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        require(tokenInput > 0, "not enough tokens");
        uint256 ethReserve = address(this).balance;
        uint256 token_reserve = token.balanceOf(address(this));
        ethOutput = price(tokenInput, token_reserve, ethReserve);
        require(
            token.transferFrom(msg.sender, address(this), tokenInput),
            "Tokens not sent!"
        ); // send tokens to contract
        (bool sent, ) = msg.sender.call{value: ethOutput}(""); // send eth to the sender who invoked this
        require(sent, "Failed to send Ether");
        emit TokenToEthSwap(msg.sender, "Tokens to ETH", ethOutput, tokenInput);
        return ethOutput;
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     * NOTE: parameter is the msg.value sent with this function call. That amount is used to determine the amount of $BAL needed as well and taken from the depositor.
     * NOTE: user has to make sure to give DEX approval to spend their tokens on their behalf by calling approve function prior to this function call.
     * NOTE: Equal parts of both assets will be removed from the user's wallet with respect to the price outlined by the AMM.
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        require(msg.value > 0, "Must send value when depositing");
        uint256 ethReserve = address(this).balance.sub(msg.value);
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 tokenDeposit;

        tokenDeposit = (msg.value.mul(tokenReserve) / ethReserve).add(1);

        uint256 liquidityMinted = msg.value.mul(totalLiquidity) / ethReserve;
        liquidity[msg.sender] = liquidity[msg.sender].add(liquidityMinted);
        totalLiquidity = totalLiquidity.add(liquidityMinted);

        require(token.transferFrom(msg.sender, address(this), tokenDeposit));
        emit LiquidityProvided(
            msg.sender,
            liquidityMinted,
            msg.value,
            tokenDeposit
        );
        return tokenDeposit;
    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     * NOTE: with this current code, the msg caller could end up getting very little back if the liquidity is super low in the pool. I guess they could see that with the UI.
     */
    function withdraw(uint256 amount)
        public
        returns (uint256 eth_amount, uint256 token_amount)
    {
        require(liquidity[msg.sender] >= amount, "not enough to withdraw!");
        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethWithdrawn;
        ethWithdrawn = (amount.mul(ethReserve) / totalLiquidity); // amount of ether in comparison to the total eth and total liq
        uint256 tokenAmount = (amount.mul(tokenReserve) / totalLiquidity); // amount of tokens in comparison to the total tokens and total liq
        liquidity[msg.sender] = liquidity[msg.sender].sub(amount);
        totalLiquidity = totalLiquidity.sub(amount);
        (bool sent, ) = msg.sender.call{value: ethWithdrawn}("");
        require(sent, "Failed to send Ether");
        require(token.transfer(msg.sender, tokenAmount), "Tokens not sent!");
        emit LiquidityRemoved(msg.sender, amount, ethWithdrawn, tokenAmount);
        return (ethWithdrawn, tokenAmount);
    }
}
