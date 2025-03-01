// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract Aisa {
    address public owner; // 当前主账户的拥有者
    mapping(address => bool) public globalWhitelistedPayees; // 全局收款白名单地址；为空则拦截

    event globalWhitelisted(address indexed _addr, bool _value); // 记录改变值到链上,通过分析链上来获取全局白名单的具体数值

    // 子账户配置
    struct SubAccount {
        address agent; // 子账户关联的地址
        uint256 lastPaymentTimestamp; // 设置的最小时间间隔；为0则不限制
        uint64 maxPerPayment; // 每笔最大支付金额；为0则不限制
        int32 paymentCount; // 当前子账户剩余支付次数；-1=则是不限制
        uint64 paymentInterval; // 支付间隔时间限制；0=不限制
        mapping(address => bool) whitelistedPayees; // 收款地址的白名单地址；为空则拦截
        mapping(address => bool) whitelistedTokens; // 支持的erc20合约地址
    }

    // 构造函数;设置主账户所有者
    constructor() {
        owner = msg.sender;
    }

    // 子账户映射
    mapping(bytes32 => SubAccount) public subAccounts; // Using keccak256(owner, agent) as key

    // 定义modifier以检查消息发送者是否为账户所有者
    modifier onlyMainOwner() {
        require(owner == msg.sender, "Incorrect owner");
        _;
    }

    // 定义modifier来检查address是否为空
    modifier notZeroAddress(address _addr) {
        require(_addr != address(0), "The address cannot be the zero address.");
        _; // 如果地址有效，继续执行被修饰的函数
    }

    /**
     * @dev 新增主账户的支付地址白名单
     */
    function addGlobalWhitelistedPayees(address _payee) external notZeroAddress(_payee) onlyMainOwner {
        // 判断是否已经存在白名单中
        require(!globalWhitelistedPayees[_payee], "Payee already in whitelist");
        globalWhitelistedPayees[_payee] = true;
        emit globalWhitelisted(_payee, true);
    }

    /**
    * @dev 从全局白名单支付者列表中移除一个支付者地址
    * @param _payee 要移除的支付者地址
    */
    function removeGlobalWhitelistedPayees(address _payee) external notZeroAddress(_payee) onlyMainOwner {
        // 判断是否已经存在白名单中
        require(globalWhitelistedPayees[_payee], "Payee not in whitelist");
        globalWhitelistedPayees[_payee] = false;
        emit globalWhitelisted(_payee, false);
    }


    /**
     * @dev 创建子账户
     * @param agent 子账户地址
     * @param whitelistedPayee 子账户的白名单支付者列表
     * @param whitelistedToken 子账户的白名单代币列表
     * @param maxPerPayment 每次支付的最大金额限制
     * @param paymentCount 支付次数限制
     * @param paymentInterval 支付间隔时间限制
     */
    function createSubAccount(
        address agent, 
        address whitelistedPayee,
        address whitelistedToken,
        uint64 maxPerPayment,
        int32 paymentCount,
        uint64 paymentInterval
    ) external notZeroAddress(agent) notZeroAddress(whitelistedPayee) notZeroAddress(whitelistedToken) onlyMainOwner {
        
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        // 初始化SubAccount结构体的基本字段
        SubAccount storage newSubAccount = subAccounts[subAccountKey];
        newSubAccount.agent = agent;
        newSubAccount.lastPaymentTimestamp = 0;
        newSubAccount.maxPerPayment = maxPerPayment;
        newSubAccount.paymentCount = paymentCount;
        newSubAccount.paymentInterval = paymentInterval;
        
        // 单独为whitelistedPayees和whitelistedTokens添加初始值
        newSubAccount.whitelistedPayees[whitelistedPayee] = true;
        newSubAccount.whitelistedTokens[whitelistedToken] = true;
    }

    /**
     * @dev 根据 agent 获取子账户详情（不含 mappings）
     * @param agent 子账户地址
     */
    function getSubAccountDetails(address agent) external view returns (
        address,
        uint256,
        uint64,
        int32,
        uint64
    ) {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        SubAccount storage account = subAccounts[subAccountKey];
        return (
            account.agent,
            account.lastPaymentTimestamp,
            account.maxPerPayment,
            account.paymentCount,
            account.paymentInterval
        );
    }

    /**
     * @dev 查询指定子账户中某个支付者的白名单状态
     * @param agent 子账户地址
     * @param payee 要查询的支付者地址
     */
    function isWhitelistedPayee(address agent, address payee) external view returns (bool) {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        return subAccounts[subAccountKey].whitelistedPayees[payee];
    }

    /**
     * @dev 查询指定子账户中某种代币的白名单状态
     * @param agent 子账户地址
     * @param token 要查询的代币地址
     */
    function isWhitelistedToken(address agent, address token) external view returns (bool) {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        return subAccounts[subAccountKey].whitelistedTokens[token];
    }

    /**
     * @dev 增加子账户对当前合约的代币授权额度
     * 
     * @param tokenAddress 代币合约地址
     * @param amount 要增加的授权额度
     */
    function increaseSubAccountAllowance(address tokenAddress, uint256 amount) external {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, msg.sender));
        SubAccount storage subAccount = subAccounts[subAccountKey];
        
        // 确保调用者是正确的子账户代理
        require(subAccount.agent == msg.sender, "Incorrect agent");

        // 确保目标代币地址在白名单中
        require(subAccount.whitelistedTokens[tokenAddress], "Token not whitelisted");

        IERC20 token = IERC20(tokenAddress);

        // 获取当前批准额度
        uint256 currentAllowance = token.allowance(msg.sender, address(this));

        // 计算新的批准额度
        uint256 newAllowance = currentAllowance + amount;

        // 调用 approve 更新批准额度
        token.approve(address(this), newAllowance);
    }

    // 减少子账户对当前合约的的授权额度
    // 只有子账户才能操作
    function decreaseSubAccountAllowance(address tokenAddress, uint256 amount) external {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, msg.sender));
        SubAccount storage subAccount = subAccounts[subAccountKey];
        require(subAccount.agent == msg.sender, "Incorrect agent");
        // 确保目标代币地址在白名单中
        require(subAccount.whitelistedTokens[tokenAddress], "Token not whitelisted");

        // 执行代币授权额度减少
        IERC20 token = IERC20(tokenAddress);
         // 获取当前批准额度
        uint256 currentAllowance = token.allowance(msg.sender, address(this));

        // 计算新的批准额度
        uint256 newAllowance = currentAllowance - amount;
        require(newAllowance <= currentAllowance, "Decrease amount exceeds allowance");

        // 调用 approve 来更新批准额度
        token.approve(address(this), newAllowance);
    }

    /**
     * @dev 支付请求;只要agent都能操作该方法
     * @param payee 收款人地址
     * @param tokenAddress 代币合约地址
     * @param amount 要支付的金额
     */
    function paymentRequest(
        address payee,
        address tokenAddress,
        uint256 amount
    ) external {
        address agent = msg.sender;
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        SubAccount storage subAccount = subAccounts[subAccountKey];
        require(subAccount.agent == agent, "Incorrect agent");

        // 验证子账户支付规则
        validateSubPaymentRule(agent, payee, amount, tokenAddress);

        // 验证主账户支付规则
        require(globalWhitelistedPayees[payee], "Payee not in whitelist");
        
        // 执行代币转账
        IERC20 token = IERC20(tokenAddress);
        token.transferFrom(msg.sender, payee, amount);

        // 减少支付次数
        subAccount.paymentCount --;
        // 更新最后支付的时间
        subAccount.lastPaymentTimestamp = block.timestamp;
    }
    
    /**
    * @dev 更新子账户的白名单支付者或代币列表
    * 
    * @param agent 子账户对应的代理地址，用于生成唯一的子账户键。
    * @param isPayee 布尔值，指示要更新的是支付者白名单还是代币白名单：
    *                - 如果为 true，则更新支付者白名单 (`whitelistedPayees`)。
    *                - 如果为 false，则更新代币白名单 (`whitelistedTokens`)。
    * @param target 要添加到白名单或从白名单中移除的目标地址（可以是支付者的地址或代币合约的地址）。
    * @param value 布尔值，指示目标地址的状态：
    *              - 如果为 true，则将目标地址添加到相应的白名单中。
    *              - 如果为 false，则从相应的白名单中移除目标地址（实际上是将其状态设置为 false）。
    */
    function updateWhitelist(address agent, bool isPayee, address target, bool value) external onlyMainOwner {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        SubAccount storage subAccount = subAccounts[subAccountKey];
        if(isPayee) {
            subAccount.whitelistedPayees[target] = value;
        } else {
            subAccount.whitelistedTokens[target] = value;
        }
    }

    /**
     * @dev 更新子账户的最大每次支付金额
     * @param agent 子账户关联的代理地址
     * @param _maxPerPayment 新的最大每次支付金额
     */
    function updateMaxPerPayment(address agent, uint64 _maxPerPayment) external onlyMainOwner {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        SubAccount storage subAccount = subAccounts[subAccountKey];
        // 更新最大每次支付金额
        subAccount.maxPerPayment = _maxPerPayment;
    }

    /**
     * @dev 更新子账户的支付次数限制
     * @param agent 子账户地址
     * @param _paymentCount 新的支付次数限制
     */
    function updatePaymentCount(address agent, int32 _paymentCount) external onlyMainOwner  {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        SubAccount storage subAccount = subAccounts[subAccountKey];
        // 更新支付次数限制
        subAccount.paymentCount = _paymentCount;
    }

    /**
     * @dev 更新子账户的支付间隔时间限制
     * @param agent 子账户关联的代理地址
     * @param _paymentInterval 新的支付间隔时间限制
     */
    function updatePaymentInterval(address agent, uint64 _paymentInterval) external onlyMainOwner  {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        SubAccount storage subAccount = subAccounts[subAccountKey];
        // 更新支付间隔时间限制
        subAccount.paymentInterval = _paymentInterval;
    }

    /**
    * @dev 验证子账户的支付规则
    * @param agent 子账户标识符
    * @param payee 支付者地址
    * @param paymentAmount 支付金额
    * @param tokenMint 代币合约地址
    */
    function validateSubPaymentRule(
        address agent,
        address payee,
        uint256 paymentAmount,
        address tokenMint
    ) internal view {
        bytes32 subAccountKey = keccak256(abi.encodePacked(owner, agent));
        SubAccount storage subAccount = subAccounts[subAccountKey];

        // 检查支付金额是否符合最大限额 (0 表示无限制)
        if (subAccount.maxPerPayment > 0) {
            require(subAccount.maxPerPayment >= paymentAmount, 
                "Payment amount exceeds limit or invalid");
        }

        // 检查支付时间间隔
        if (subAccount.paymentInterval > 0) {
            require(block.timestamp >= subAccount.lastPaymentTimestamp + subAccount.paymentInterval, 
                "Payment interval not met");
        }

        // 检查剩余支付次数 (-1 表示无限制)
        require(subAccount.paymentCount == -1 || subAccount.paymentCount > 0, 
            "Insufficient payment count remaining");

        // 检查收款地址是否在白名单中
        require(subAccount.whitelistedPayees[payee], "Payee is not whitelisted");

        // 检查代币合约地址是否在白名单中
        require(subAccount.whitelistedTokens[tokenMint], "Token contract is not whitelisted");
    }
}