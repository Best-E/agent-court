// Chainlink Functions source code
// Args: [taskId, taskProofHash, completionProofHash, clientEvidenceHash, agentEvidenceHash]
// Secrets: OPENAI_API_KEY

const taskId = args[0];
const taskProofHash = args[1];
const completionProofHash = args[2];
const clientEvidenceHash = args[3];
const agentEvidenceHash = args[4];

// 1. Fetch evidence from IPFS/HTTP - replace with your storage
// For v1, we'll just pass hashes to the LLM and let it reason on the prompt
// In production: const taskDesc = await Functions.makeHttpRequest({url: `https://ipfs.io/ipfs/${taskProofHash}`})

const prompt = `
You are a judge in Agent Court. A client hired an AI agent. The agent claims completion. The client disputes.

Task ID: ${taskId}
Original task proof hash: ${taskProofHash}
Agent completion proof hash: ${completionProofHash}
Client evidence hash: ${clientEvidenceHash}
Agent evidence hash: ${agentEvidenceHash}

Rules:
1. If the agent's completion proof reasonably satisfies the original task description, the agent wins.
2. If the agent failed, was malicious, or proof is missing/invalid, the client wins.
3. Be strict but fair. Agents should be paid if they delivered.

Return ONLY a single number with no explanation:
0 = Agent wins, escrow goes to agent
1 = Client wins, escrow refunded to client
`;

const openaiRequest = Functions.makeHttpRequest({
  url: "https://api.openai.com/v1/chat/completions",
  method: "POST",
  headers: {
    "Authorization": `Bearer ${secrets.OPENAI_API_KEY}`,
    "Content-Type": "application/json",
  },
  data: {
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: prompt }],
    temperature: 0,
    max_tokens: 1,
  },
});

const openaiResponse = await openaiRequest;
if (openaiResponse.error) {
  throw Error("OpenAI request failed");
}

const result = openaiResponse.data.choices[0].message.content.trim();

// Validate: must be "0" or "1"
if (result!== "0" && result!== "1") {
  throw Error(`Invalid LLM response: ${result}`);
}

// Return bytes - encoded uint8
return Functions.encodeUint256(Number(result));
