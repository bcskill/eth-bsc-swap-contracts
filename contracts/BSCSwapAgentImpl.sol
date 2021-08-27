pragma solidity 0.6.4;

import "./interfaces/ISwap.sol";
import "./interfaces/IERC20Query.sol";
import "./bep20/BEP20UpgradeableProxy.sol";
import './interfaces/IProxyInitialize.sol';
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/proxy/Initializable.sol";
import "openzeppelin-solidity/contracts/GSN/Context.sol";

contract  BSCSwapAgentImpl is Context, Initializable {


    using SafeERC20 for IERC20;

    mapping(address => address) public swapMappingMain2Side;
    mapping(address => address) public swapMappingSide2Main;
    mapping(bytes32 => bool) public filledETHTx;
    mapping(bytes32 => bool) public createSwapPairTx;

    address payable public owner;
    address public bep20ProxyAdmin;
    address public bep20Implementation;
    uint256 public swapFee;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SwapPairCreated(bytes32 indexed mainChainTxHash, address indexed mainChainErc20Addr, address indexed sideChainErc20Addr, string name, string symbol, uint8 decimals);
    event SwapStarted(address indexed bep20Addr, address indexed erc20Addr, address indexed fromAddr, uint256 amount, uint256 feeAmount);
    event SwapFilled(address indexed bep20Addr, bytes32 indexed ethTxHash, address indexed toAddress, uint256 amount);

    constructor() public {
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    modifier notContract() {
        require(!isContract(msg.sender), "contract is not allowed to swap");
        require(msg.sender == tx.origin, "no proxy contract is allowed");
       _;
    }



    function initialize(address bep20Impl, uint256 fee, address payable ownerAddr, address bep20ProxyAdminAddr) public initializer {
        bep20Implementation = bep20Impl;
        swapFee = fee;
        owner = ownerAddr;
        bep20ProxyAdmin = bep20ProxyAdminAddr;
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    /**
    * @dev Leaves the contract without owner. It will not be possible to call
    * `onlyOwner` functions anymore. Can only be called by the current owner.
    *
    * NOTE: Renouncing ownership will leave the contract without an owner,
    * thereby removing any functionality that is only available to the owner.
    */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address payable newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Returns set minimum swap fee from BEP20 to ERC20
     */
    function setSwapFee(uint256 fee) onlyOwner external {
        swapFee = fee;
    }

    /**
     * @dev createSwapPair
     */
    function createSwapPair(bytes32 mainChainTxHash, address mainChainErc20Addr, address sideChainErc20Addr, string calldata name, string calldata symbol, uint8 decimals) onlyOwner external returns (bool) {
        require(!createSwapPairTx[mainChainTxHash], "main chain tx hash created already");
        require(swapMappingMain2Side[mainChainErc20Addr] == address(0x0), "duplicated main chain swap pair");
        require(swapMappingSide2Main[sideChainErc20Addr] == address(0x0), "duplicated side chain  swap pair");

        string memory mainChainErc20Name = IERC20Query(mainChainErc20Addr).name();
        string memory mainChainErc20Symbol = IERC20Query(mainChainErc20Addr).symbol();
        uint8 mainChainErc20Decimals = IERC20Query(mainChainErc20Addr).decimals();

        require(keccak256(abi.encodePacked(mainChainErc20Name)) == keccak256(abi.encodePacked(name)), "main chain tx hash created already");
        require(keccak256(abi.encodePacked(mainChainErc20Symbol)) == keccak256(abi.encodePacked(symbol)), "main chain tx hash created already");
        require(mainChainErc20Decimals == decimals, "main chain tx hash created already");

        swapMappingMain2Side[mainChainErc20Addr] = sideChainErc20Addr;
        swapMappingSide2Main[sideChainErc20Addr] = mainChainErc20Addr;

        emit SwapPairCreated(mainChainTxHash, mainChainErc20Addr, sideChainErc20Addr, name, symbol, decimals);
        return true;
    }

    /**
     * @dev fillETH2BSCSwap
     */
    function fillETH2BSCSwap(bytes32 ethTxHash, address erc20Addr, address toAddress, uint256 amount) onlyOwner external returns (bool) {
        require(!filledETHTx[ethTxHash], "eth tx filled already");
        address bscTokenAddr = swapMappingMain2Side[erc20Addr];
        require(bscTokenAddr != address(0x0), "no swap pair for this token");
        filledETHTx[ethTxHash] = true;
        ISwap(bscTokenAddr).mintTo(amount, toAddress);
        emit SwapFilled(bscTokenAddr, ethTxHash, toAddress, amount);

        return true;
    }
    /**
     * @dev swapBSC2ETH
     */
    function swapBSC2ETH(address bep20Addr, uint256 amount) payable external notContract returns (bool) {
        address erc20Addr = swapMappingSide2Main[bep20Addr];
        require(erc20Addr != address(0x0), "no swap pair for this token");
        require(msg.value == swapFee, "swap fee not equal");

        IERC20(bep20Addr).safeTransferFrom(msg.sender, address(this), amount);
        ISwap(bep20Addr).burn(amount);
        if (msg.value != 0) {
            owner.transfer(msg.value);
        }

        emit SwapStarted(bep20Addr, erc20Addr, msg.sender, amount, msg.value);
        return true;
    }
}