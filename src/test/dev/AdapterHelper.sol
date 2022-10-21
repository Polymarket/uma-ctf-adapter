// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import { Deployer } from "./Deployer.sol";
import { TestHelper } from "./TestHelper.sol";
import { MintableERC20 } from "./MintableERC20.sol";
import { OracleStub } from "./OracleStub.sol";

import { UmaCtfAdapter } from "src/UmaCtfAdapter.sol";
import { IFinder } from "src/interfaces/IFinder.sol";
import { IAddressWhitelist } from "src/interfaces/IAddressWhitelist.sol";

import { IAuthEE } from "src/interfaces/IAuth.sol";
import { IConditionalTokens } from "src/interfaces/IConditionalTokens.sol";
import { IOptimisticOracleV2, Request } from "src/interfaces/IOptimisticOracleV2.sol";
import { QuestionData, IUmaCtfAdapterEE } from "src/interfaces/IUmaCtfAdapter.sol";

struct Unsigned {
    uint256 rawValue;
}

interface IStore {
    function setFinalFee(address currency, Unsigned memory newFinalFee) external;
}

interface IIdentifierWhitelist {
    function addSupportedIdentifier(bytes32) external;
}

abstract contract AdapterHelper is TestHelper, IAuthEE, IUmaCtfAdapterEE {
    address public admin = alice;
    address public proposer = brian;
    address public disputer = henry;
    UmaCtfAdapter public adapter;
    address public usdc;
    address public ctf;
    address public optimisticOracle;
    address public finder;
    address public whitelist;
    OracleStub public oracle;

    bytes32 public conditionId;

    bytes public constant ancillaryData =
        hex"569e599c2f623949c0d74d7bf006f8a4f68b911876d6437c1db4ad4c3eb21e68682fb8168b75eb23d3994383a40643d73d59";
    bytes32 public constant questionID = keccak256(ancillaryData);
    bytes32 public constant identifier = "YES_OR_NO_QUERY";

    event Transfer(address indexed from, address indexed to, uint256 value);

    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount,
        uint256[] payoutNumerators
    );

    function setUp() public virtual {
        vm.label(admin, "Admin");
        vm.label(proposer, "Proposer");
        vm.label(disputer, "Disputer");

        // Deploy Collateral and ConditionalTokens Framework
        usdc = deployToken("USD Coin", "USD");
        vm.label(usdc, "USDC");
        ctf = Deployer.ConditionalTokens();

        // Setup UMA Contracts
        setupUmaContracts();

        // Deploy adapter
        vm.startPrank(admin);
        adapter = new UmaCtfAdapter(ctf, finder);

        conditionId = IConditionalTokens(ctf).getConditionId(address(adapter), questionID, 2);

        // Mint USDC to Admin and approve on Adapter
        dealAndApprove(usdc, admin, address(adapter), 1_000_000_000_000);
        vm.stopPrank();

        // Mint USDC to Proposer and Disputer and approve the OptimisticOracle as spender
        vm.startPrank(proposer);
        dealAndApprove(usdc, proposer, optimisticOracle, 1_000_000_000_000);
        vm.stopPrank();

        vm.startPrank(disputer);
        dealAndApprove(usdc, disputer, optimisticOracle, 1_000_000_000_000);
        vm.stopPrank();
    }

    function setupUmaContracts() internal {
        // Deploy Store
        address store = Deployer.Store();
        // Set final fee for USDC
        IStore(store).setFinalFee(usdc, Unsigned({rawValue: 1500000000}));

        address identifierWhitelist = Deployer.IdentifierWhitelist();
        // Add YES_OR_NO_QUERY to Identifier Whitelist
        IIdentifierWhitelist(identifierWhitelist).addSupportedIdentifier("YES_OR_NO_QUERY");

        // Deploy Collateral whitelist
        whitelist = Deployer.AddressWhitelist();
        // Add USDC to whitelist
        IAddressWhitelist(whitelist).addToWhitelist(usdc);

        // Deploy Oracle(Voting)
        oracle = new OracleStub();

        // Deploy Finder
        finder = Deployer.Finder();
        // Deploy Optimistic Oracle
        optimisticOracle = Deployer.OptimisticOracleV2(7200, finder);

        // Add contracts to Finder
        IFinder(finder).changeImplementationAddress("IdentifierWhitelist", identifierWhitelist);
        IFinder(finder).changeImplementationAddress("Store", store);
        IFinder(finder).changeImplementationAddress("OptimisticOracleV2", optimisticOracle);
        IFinder(finder).changeImplementationAddress("CollateralWhitelist", whitelist);
        IFinder(finder).changeImplementationAddress("Oracle", address(oracle));
    }

    function settle(uint256 timestamp, bytes memory data) internal {
        fastForward(10);
        vm.prank(proposer);
        IOptimisticOracleV2(optimisticOracle).settle(address(adapter), identifier, timestamp, data);
    }

    function getRequest(uint256 timestamp, bytes memory data) internal view returns (Request memory) {
        return IOptimisticOracleV2(optimisticOracle).getRequest(address(adapter), identifier, timestamp, data);
    }

    function propose(int256 price, uint256 timestamp, bytes memory data) internal {
        fastForward(10);
        vm.prank(proposer);
        IOptimisticOracleV2(optimisticOracle).proposePrice(address(adapter), identifier, timestamp, data, price);
    }

    function dispute(uint256 timestamp, bytes memory data) internal {
        fastForward(10);
        vm.prank(disputer);
        IOptimisticOracleV2(optimisticOracle).disputePrice(address(adapter), identifier, timestamp, data);
    }

    function proposeAndSettle(int256 price, uint256 timestamp, bytes memory data) internal {
        // Propose a price for the request
        propose(price, timestamp, data);

        // Advance time past the request expiration time
        fastForward(1000);

        // Settle the request
        settle(timestamp, data);
    }

    function deployToken(string memory name, string memory symbol) internal returns (address token) {
        token = address(new MintableERC20(name, symbol));
    }
}
