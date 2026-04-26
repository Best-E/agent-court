# Security Policy

## Reporting a Vulnerability

**Do not open public GitHub issues for security bugs.**

If you discover a vulnerability in Agent Court contracts, SDK, or infrastructure:

1. Email: security@yourdomain.com
2. Include: description, reproduction steps, potential impact
3. Encrypt to our PGP key if possible: [link to key]

We commit to:
- Acknowledge receipt within 48 hours
- Provide timeline for fix within 7 days
- Credit you in release notes unless you prefer anonymity

Bug bounty: Critical bugs affecting user funds eligible for up to $10,000 USDC at our discretion.

## Smart Contract Security

### Design Principles
1. **Immutability first**: v1 contracts have no owner, no upgrade path, no pause. What deploys is final.
2. **Minimal trust**: Chainlink Functions jury cannot steal funds, only return `0` or `1` to settle existing escrow.
3. **Fail-safe defaults**: Disputes default to agent if jury call fails. Better to overpay than lock funds.

### Known Risks
| Risk | Mitigation |
| --- | --- |
| LLM jury returns wrong verdict | Prompt constrained to `0/1`. v2 adds multi-LLM consensus + slashing |
| Stake token != USDC | `AgentRegistry` deploys with immutable `stakeToken`. Verify on Basescan |
| Reentrancy on callbacks | `TaskEscrow` uses Checks-Effects-Interactions + `nonReentrant` |
| Front-running dispute resolution | Not applicable - verdict comes from Chainlink DON only |

### Audit Status
- **v1.0.0**: Internal review only. Not audited.
- **Mainnet**: Do not deploy >$100k TVL without external audit.
- **Tools run**: `slither`, `aderyn`, `hardhat test` 100% pass required.

## Contributor Security Requirements

Anyone with `Write` access to this repo must:

1. **Never commit secrets**
   - `.env` is gitignored. Use `.env.example` for templates
   - No private keys, API keys, or mnemonics in code/comments/tests
   - If you accidentally commit a secret: rotate it immediately and force-push to remove

2. **Branch protection**
   - No direct pushes to `main`
   - All changes via PR with 1 approval from codeowner
   - `main` must pass CI: `compile`, `test`, `slither`

3. **Dependency review**
   - New packages require approval. Run `npm audit` before PR
   - Pin versions. No `latest` in `package.json`

4. **Code review checklist**
   - [ ] No `selfdestruct`, `delegatecall`, or `tx.origin`
   - [ ] All external calls use `call` with reentrancy guard
   - [ ] Events emitted for all state changes
   - [ ] NatSpec on all public/external functions
   - [ ] Tests cover new code + edge cases

5. **Key management**
   - Contributors never receive mainnet deployer keys
   - Testnet keys only, funded with valueless Sepolia ETH
   - Production deploys done via hardware wallet or Safe multisig

## Deployment Security

### Mainnet Deploy Checklist
- [ ] `PRIVATE_KEY` is hardware wallet or Safe signer
- [ ] `hardhat.config.js` RPC URLs use private node, not public
- [ ] Verify all constructor args on Basescan match expected
- [ ] Transfer `AgentRegistry` ownership to `TaskEscrow` immediately after deploy
- [ ] Add `LLMJuryVerifier` as Functions consumer + fund subscription
- [ ] Revoke deployer EOA from any `onlyOwner` roles if present
- [ ] Announce addresses + verify on GitHub Releases

### Emergency Response
If exploit detected:
1. Pause new task creation: set `TaskEscrow` param if pause exists, else social announcement
2. Snapshot affected balances
3. Deploy patched version + migration plan
4. Post-mortem within 72 hours

Contact: security@yourdomain.com or on-chain message to deployer address.

## Supply Chain

- Contracts use OpenZeppelin v5.0.2 - audited library
- Chainlink Functions - decentralized oracle network
- Build artifacts reproducible: `npx hardhat compile` + compare bytecode

## License
Apache-2.0. Use at your own risk. No warranty.
