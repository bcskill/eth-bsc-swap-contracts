pragma solidity 0.6.4;

import "./interfaces/IERC20Query.sol";
import "openzeppelin-solidity/contracts/proxy/Initializable.sol";
import "openzeppelin-solidity/contracts/GSN/Context.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";

contract ETHSwapAgentImpl is Context, Initializable {

    using SafeERC20 for IERC20;

    mapping(address => bool) public registeredMain;
    mapping(bytes32 => bool) public filledBSCTx;
    address payable public owner;
    uint256 public swapFee;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SwapPairRegister(address indexed sponsor,address indexed mainChainErc20Addr, string name, string symbol, uint8 decimals);
    event SwapStarted(address indexed mainChainErc20Addr, address indexed sideChainFromAddr, uint256 amount, uint256 feeAmount);
    event SwapFilled(address indexed mainChainErc20Addr, bytes32 indexed sideChainTxHash, address indexed mainChainToAddr, uint256 amount);

    constructor() public {
    }

    modifier onlyOwner() {
        require(owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function initialize(uint256 fee, address payable ownerAddr) public initializer {
        swapFee = fee;
        owner = ownerAddr;
    }

    modifier notContract() {
        require(!isContract(msg.sender), "contract is not allowed to swap");
        require(msg.sender == tx.origin, "no proxy contract is allowed");
       _;
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    function transferOwnership(address payable newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setSwapFee(uint256 fee) onlyOwner external {
        swapFee = fee;
    }

    function registerSwapPairToSide(address mainChainErc20Addr) external returns (bool) {
        require(!registeredMain[mainChainErc20Addr], "already registered");

        string memory name = IERC20Query(mainChainErc20Addr).name();
        string memory symbol = IERC20Query(mainChainErc20Addr).symbol();
        uint8 decimals = IERC20Query(mainChainErc20Addr).decimals();

        require(bytes(name).length>0, "empty name");
        require(bytes(symbol).length>0, "empty symbol");

        registeredMain[mainChainErc20Addr] = true;

        emit SwapPairRegister(msg.sender, mainChainErc20Addr, name, symbol, decimals);
        return true;
    }

    function fillSide2MainSwap(bytes32 sideChainTxHash, address mainChainErc20Addr, address mainChainToAddr, uint256 amount) onlyOwner external returns (bool) {
        require(!filledBSCTx[sideChainTxHash], "bsc tx filled already");
        require(registeredMain[mainChainErc20Addr], "not registered token");
        require(IERC20(mainChainErc20Addr).balanceOf(msg.sender) >= amount, "Insufficient contract account balance");

        filledBSCTx[sideChainTxHash] = true;
        IERC20(mainChainErc20Addr).safeTransfer(mainChainToAddr, amount);

        emit SwapFilled(mainChainErc20Addr, sideChainTxHash, mainChainToAddr, amount);
        return true;
    }

    function swapMain2Side(address mainChainErc20Addr, uint256 amount) payable external notContract returns (bool) {
        require(registeredMain[mainChainErc20Addr], "not registered token");
        require(msg.value == swapFee, "swap fee not equal");

        IERC20(mainChainErc20Addr).safeTransferFrom(msg.sender, address(this), amount);
        if (msg.value != 0) {
            owner.transfer(msg.value);
        }

        emit SwapStarted(mainChainErc20Addr, msg.sender, amount, msg.value);
        return true;
    }
}