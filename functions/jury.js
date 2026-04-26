// Chainlink Functions source for LLM Jury
// args[0] = taskId
// args[1] = escrowAddress
// args[2] = clientClaim
// args[3] = agentClaim
// args[4] = proofHash

const taskId = args[0];
const escrowAddress = args[1];
const clientClaim = args[2];
const agentClaim = args[3];
const proofHash = args[4];

if (!secrets.openaiKey) {
  throw Error("OPENAI_KEY not set in secrets");
}

const prompt = `
You are an impartial jury for a Web3 task dispute.

Task ID: ${taskId}
Escrow Contract: ${escrowAddress}
Proof Hash: ${proofHash}

Client Position: ${clientClaim}
Agent Position: ${agentClaim}

Instructions:
1. Review both positions. Assume the proofHash links to IPFS evidence.
2. Decide if the agent completed the task as agreed.
3. Respond ONLY with a single digit: 1 if agent won, 0 if client won.
4. No explanation. No other text.

Decision:`;

const openaiRequest = Functions.makeHttpRequest({
  url: "https://api.openai.com/v1/chat/completions",
  method: "POST",
  headers: {
    "Authorization": `Bearer ${secrets.openaiKey}`,
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
  throw Error(`OpenAI error: ${openaiResponse.message}`);
}

const result = openaiResponse.data.choices[0].message.content.trim();
if (result!== "0" && result!== "1") {
  throw Error(`Invalid LLM response: ${result}`);
}

// Return 1 for agent win, 0 for client win
return Functions.encodeUint256(Number(result));
