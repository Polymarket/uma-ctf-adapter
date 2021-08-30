const adapterAbi = [
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "conditionalTokenAddress",
                "type": "address"
            },
            {
                "internalType": "address",
                "name": "optimisticOracleAddress",
                "type": "address"
            }
        ],
        "stateMutability": "nonpayable",
        "type": "constructor"
    },
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "internalType": "address",
                "name": "previousOwner",
                "type": "address"
            },
            {
                "indexed": true,
                "internalType": "address",
                "name": "newOwner",
                "type": "address"
            }
        ],
        "name": "OwnershipTransferred",
        "type": "event"
    },
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            },
            {
                "indexed": false,
                "internalType": "bytes",
                "name": "question",
                "type": "bytes"
            },
            {
                "indexed": false,
                "internalType": "uint256",
                "name": "resolutionTime",
                "type": "uint256"
            },
            {
                "indexed": false,
                "internalType": "address",
                "name": "rewardToken",
                "type": "address"
            },
            {
                "indexed": false,
                "internalType": "uint256",
                "name": "reward",
                "type": "uint256"
            }
        ],
        "name": "QuestionInitialized",
        "type": "event"
    },
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "internalType": "bytes32",
                "name": "questionId",
                "type": "bytes32"
            },
            {
                "indexed": true,
                "internalType": "bool",
                "name": "emergencyReport",
                "type": "bool"
            }
        ],
        "name": "QuestionResolved",
        "type": "event"
    },
    {
        "anonymous": false,
        "inputs": [
            {
                "indexed": true,
                "internalType": "bytes32",
                "name": "identifier",
                "type": "bytes32"
            },
            {
                "indexed": true,
                "internalType": "uint256",
                "name": "timestamp",
                "type": "uint256"
            },
            {
                "indexed": true,
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            },
            {
                "indexed": false,
                "internalType": "bytes",
                "name": "ancillaryData",
                "type": "bytes"
            }
        ],
        "name": "ResolutionDataRequested",
        "type": "event"
    },
    {
        "inputs": [],
        "name": "conditionalTokenContract",
        "outputs": [
            {
                "internalType": "contract IConditionalTokens",
                "name": "",
                "type": "address"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            },
            {
                "internalType": "uint256[]",
                "name": "payouts",
                "type": "uint256[]"
            }
        ],
        "name": "emergencyReportPayouts",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "emergencySafetyPeriod",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "identifier",
        "outputs": [
            {
                "internalType": "bytes32",
                "name": "",
                "type": "bytes32"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            },
            {
                "internalType": "bytes",
                "name": "ancillaryData",
                "type": "bytes"
            },
            {
                "internalType": "uint256",
                "name": "resolutionTime",
                "type": "uint256"
            },
            {
                "internalType": "address",
                "name": "rewardToken",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "reward",
                "type": "uint256"
            }
        ],
        "name": "initializeQuestion",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "optimisticOracleContract",
        "outputs": [
            {
                "internalType": "contract IOptimisticOracle",
                "name": "",
                "type": "address"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "owner",
        "outputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "",
                "type": "bytes32"
            }
        ],
        "name": "questions",
        "outputs": [
            {
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            },
            {
                "internalType": "bytes",
                "name": "ancillaryData",
                "type": "bytes"
            },
            {
                "internalType": "uint256",
                "name": "resolutionTime",
                "type": "uint256"
            },
            {
                "internalType": "address",
                "name": "rewardToken",
                "type": "address"
            },
            {
                "internalType": "uint256",
                "name": "reward",
                "type": "uint256"
            },
            {
                "internalType": "bool",
                "name": "resolutionDataRequested",
                "type": "bool"
            },
            {
                "internalType": "bool",
                "name": "resolved",
                "type": "bool"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            }
        ],
        "name": "readyToReportPayouts",
        "outputs": [
            {
                "internalType": "bool",
                "name": "",
                "type": "bool"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            }
        ],
        "name": "readyToRequestResolution",
        "outputs": [
            {
                "internalType": "bool",
                "name": "",
                "type": "bool"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "renounceOwnership",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            }
        ],
        "name": "reportPayouts",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "questionID",
                "type": "bytes32"
            }
        ],
        "name": "requestResolutionData",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "newOwner",
                "type": "address"
            }
        ],
        "name": "transferOwnership",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    }
]

export default adapterAbi;