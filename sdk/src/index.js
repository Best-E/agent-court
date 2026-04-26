import { ethers, Contract, Signer, ContractTransactionResponse, Interface } from "ethers";

// ABIs - copy from artifacts after `npx hardhat compile`
import AgentRegistryABI from "./contracts/abis/AgentRegistry.json";
import TaskEscrowABI from "./contracts/abis/TaskEscrow.json";
import PaymentIntentABI from "./contracts/abis/PaymentIntent.json";
import ERC20ABI from "./contracts/abis/ERC20.json";

export interface AgentCourtConfig {
  signer: Signer;
  chainId: number;
  addresses: {
    registry: string;
    escrow: string;
    paymentIntent: string;
    usdc?: string;
  };
}

export interface RegisterAgentParams {
  metadataHash: string; // bytes32
  stakeToken: string;
  stakeAmount: bigint;
}

export interface CreateTaskParams {
  agentId: bigint;
  amount: bigint;
  proofHash: string; // bytes32
}

export interface Task {
  id: bigint;
  clientId: bigint;
  agentId: bigint;
  amount: bigint;
  status: number; // 0: Created, 1: Completed, 2: Disputed, 3: Resolved
  proofHash: string;
  completionProofHash: string;
}

export interface Agent {
  id: bigint;
  owner: string;
  metadataHash: string;
  stakeAmount: bigint;
  active: boolean;
  tasksCompleted: bigint;
  tasksDisputed: bigint;
  totalEarned: bigint;
}

export class AgentCourt {
  private registry: Contract;
  private escrow: Contract;
  private paymentIntent: Contract;
  private signer: Signer;

  constructor(config: AgentCourtConfig) {
    this.signer = config.signer;
    this.registry = new Contract(config.addresses.registry, AgentRegistryABI, config.signer);
    this.escrow = new Contract(config.addresses.escrow, TaskEscrowABI, config.signer);
    this.paymentIntent = new Contract(config.addresses.paymentIntent, PaymentIntentABI, config.signer);
  }

  // Registry methods
  async registerAgent(params: RegisterAgentParams): Promise<ContractTransactionResponse> {
    const usdc = new Contract(params.stakeToken, ERC20ABI, this.signer);
    await usdc.approve(await this.registry.getAddress(), params.stakeAmount);
    return this.registry.registerAgent(params.metadataHash, await this.signer.getAddress());
  }

  async getAgent(agentId: bigint): Promise<Agent> {
    const data = await this.registry.getAgent(agentId);
    return {
      id: data.id,
      owner: data.owner,
      metadataHash: data.metadataHash,
      stakeAmount: data.stakeAmount,
      active: data.active,
      tasksCompleted: data.tasksCompleted,
      tasksDisputed: data.tasksDisputed,
      totalEarned: data.totalEarned,
    };
  }

  async getAgentId(owner: string): Promise<bigint> {
    return this.registry.ownerToId(owner);
  }

  // Escrow methods
  async createTask(params: CreateTaskParams): Promise<ContractTransactionResponse> {
    const usdcAddr = await this.registry.stakeToken();
    const usdc = new Contract(usdcAddr, ERC20ABI, this.signer);
    await usdc.approve(await this.escrow.getAddress(), params.amount);
    return this.escrow.createTask(params.agentId, params.amount, params.proofHash);
  }

  async completeTask(taskId: bigint, proofHash: string): Promise<ContractTransactionResponse> {
    return this.escrow.completeTask(taskId, proofHash);
  }

  async approveTask(taskId: bigint): Promise<ContractTransactionResponse> {
    return this.escrow.approveTask(taskId);
  }

  async disputeTask(taskId: bigint): Promise<ContractTransactionResponse> {
    return this.escrow.disputeTask(taskId);
  }

  async getTask(taskId: bigint): Promise<Task> {
    const data = await this.escrow.getTask(taskId);
    return {
      id: data.id,
      clientId: data.clientId,
      agentId: data.agentId,
      amount: data.amount,
      status: Number(data.status),
      proofHash: data.proofHash,
      completionProofHash: data.completionProofHash,
    };
  }

  // PaymentIntent methods
  async pay(agentId: bigint, amount: bigint, metadataHash: string): Promise<ContractTransactionResponse> {
    const usdcAddr = await this.registry.stakeToken();
    const usdc = new Contract(usdcAddr, ERC20ABI, this.signer);
    await usdc.approve(await this.paymentIntent.getAddress(), amount);
    return this.paymentIntent.pay(agentId, amount, metadataHash);
  }

  async claim(): Promise<ContractTransactionResponse> {
    return this.paymentIntent.claim();
  }

  async getPendingClaims(agentId: bigint): Promise<bigint> {
    return this.paymentIntent.pendingClaims(agentId);
  }

  // Helpers
  parseTaskId(receipt: ethers.ContractTransactionReceipt): bigint {
    const iface = new Interface(TaskEscrowABI);
    for (const log of receipt.logs) {
      try {
        const parsed = iface.parseLog(log);
        if (parsed?.name === "TaskCreated") {
          return parsed.args.taskId;
        }
      } catch {}
    }
    throw new Error("TaskCreated event not found");
  }

  static addresses = {
    baseSepolia: {
      chainId: 84532,
      registry: "0x...", // fill after deploy
      escrow: "0x...",
      paymentIntent: "0x...",
      usdc: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", // Base Sepolia USDC
    },
    base: {
      chainId: 8453,
      registry: "0x...", // fill after mainnet deploy
      escrow: "0x...",
      paymentIntent: "0x...",
      usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // Base USDC
    },
  };
}
