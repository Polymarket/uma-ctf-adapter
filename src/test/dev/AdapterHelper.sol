// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Deployer } from "./Deployer.sol";
import { TestHelper } from "./TestHelper.sol";
import { USDC } from "./USDC.sol";

import { UmaCtfAdapter } from "src/UmaCtfAdapter.sol";

import { IFinder } from "src/interfaces/IFinder.sol";
import { IAddressWhitelist } from "src/interfaces/IAddressWhitelist.sol";

import { IAuthEE } from "src/interfaces/IAuth.sol";
import { QuestionData, IUmaCtfAdapterEE } from "src/interfaces/IUmaCtfAdapter.sol";

import { console2 as console } from "forge-std/console2.sol";

struct Data {
    uint256 requestTimestamp;
    uint256 reward;
    uint256 proposalBond;
    uint256 adminResolutionTimestamp;
    bool resolved;
    bool paused;
    address rewardToken;
    address creator;
    bytes ancillaryData;
}

struct Unsigned {
    uint256 rawValue;
}
interface IStore {
    function setFinalFee(address currency, Unsigned memory newFinalFee) external;
}

abstract contract AdapterHelper is TestHelper, IAuthEE, IUmaCtfAdapterEE {
    address public admin = alice;
    UmaCtfAdapter public adapter;
    address public usdc;
    address public ctf;
    address public optimisticOracle;
    address public finder;
    address public whitelist;

    uint256 internal twoHours = 7200;

    function setUp() public virtual {
        usdc = address(new USDC());
        ctf = Deployer.ConditionalTokens();
        
        // UMA Contracts Setup
        // Deploy Store
        address store = Deployer.Store();
        // Set final fee for USDC
        IStore(store).setFinalFee(usdc, Unsigned({rawValue: 1500000000}));

        address identifierWhitelist = Deployer.IdentifierWhitelist();
        // Add YES_OR_NO_QUERY to Identifier Whitelist
        identifierWhitelist.call(abi.encodeWithSignature("addSupportedIdentifier(bytes32)", bytes32("YES_OR_NO_QUERY")));
        
        // Deploy Collateral whitelist
        whitelist = Deployer.AddressWhitelist();
        // Add USDC to whitelist
        IAddressWhitelist(whitelist).addToWhitelist(usdc);

        // Deploy Finder
        finder = Deployer.Finder();
        // Deploy Optimistic Oracle
        optimisticOracle = Deployer.OptimisticOracleV2(twoHours, finder);
        
        // Add Identifier, Store, Whitelist and Optimistic Oracle to Finder
        IFinder(finder).changeImplementationAddress("IdentifierWhitelist", identifierWhitelist);
        IFinder(finder).changeImplementationAddress("Store", store);
        IFinder(finder).changeImplementationAddress("OptimisticOracleV2", optimisticOracle);
        IFinder(finder).changeImplementationAddress("CollateralWhitelist", whitelist);
        
        // Deploy adapter
        vm.prank(admin);
        adapter = new UmaCtfAdapter(ctf, finder);

        // Mint USDC to Admin and approve on Adapter
        dealAndApprove(usdc, admin, address(adapter), 1_000_000_000);
    }

    function getData(bytes32 questionID) public view returns (Data memory) {
        (
            uint256 requestTimestamp,
            uint256 reward,
            uint256 proposalBond,
            uint256 adminResolutionTimestamp,
            bool resolved,
            bool paused,
            address rewardToken,
            address creator,
            bytes memory ancillaryData
        ) = adapter.questions(questionID);
        return Data({
            creator: creator,
            requestTimestamp: requestTimestamp,
            ancillaryData: ancillaryData,
            rewardToken: rewardToken,
            reward: reward,
            proposalBond: proposalBond,
            resolved: resolved,
            paused: paused,
            adminResolutionTimestamp: adminResolutionTimestamp
        });
    }
}
