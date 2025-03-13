import ballerina/http;
import ballerina/lang.regexp;
import ballerinax/ai.agent;
import ballerinax/azure.openai.chat;

configurable string apiKey = ?;
configurable string serviceUrl = ?;
configurable string apiVersion = ?;
configurable string deploymentId = ?;

final agent:Model model = check new agent:AzureOpenAiModel(serviceUrl, apiKey, deploymentId, apiVersion);
final agent:Agent agent = check new (
    systemPrompt = {
        role: "Expense Claim Assistant",
        instructions: "You are an expense claim assistant for WSO2 employees. " +
        "Employees submit claim requests via Telegram, and your role is to create the expense claim on their behalf. " +
        "Always confirm the details with the employee before proceeding to ensure accuracy. " +
        "If any details are unclear, ask the employee for clarification before taking action. " +
        "Encourage employees to upload the receipt first, so you can extract details from it rather than " +
        "requesting all information manually."
    },
    model = model,
    tools = [createExpenseClaim, extractDetailsFromImage],
);

final http:Client expenseClient = check new ("localhost:9090");

@agent:Tool
isolated function createExpenseClaim(ExpenseClaimRequest claim) returns ExpenseClaimResponse|error {
    return expenseClient->/claims.post(claim);
}

final chat:Client azureChatClient = check new (config = {auth: {apiKey: apiKey}}, serviceUrl = serviceUrl);

# Given an image URL, process the image to extract necessary values for an expense claim.  
# + imageUrl - URL of the image to be processed.  
# + return - JSON response on success; otherwise, an error.  
@agent:Tool
isolated function extractDetailsFromImage(string imageUrl) returns json|error {
    string visionSystemPrompt = string `
You are a vision assistant. Given a receipt image URL,
your task is to process the image and extract the following information:
- Total amount
- Expense date
- Expense type (food, travel, entertainment, or other)
- Currency Code

After extracting the details, return the information in a validation JSON format like this example: 
{"total": 1000, "date": "2025-03-30", "type": "food", "currency": "USD"}

If any field cannot be determined, don't add that field in the json response.`;

    chat:CreateChatCompletionRequest completionRequest = {
        messages: [
            {
                role: "system",
                "content": visionSystemPrompt
            },
            {
                role: "user",
                "content": [
                    {"type": "text", "text": "Populate the JSON with data from this image."},
                    {"type": "image_url", "image_url": {"url": imageUrl}}
                ]
            }
        ]
    };

    chat:CreateChatCompletionResponse response = check azureChatClient->/deployments/[deploymentId]/chat/completions.post(apiVersion, completionRequest);
    var choices = response.choices;
    if choices is () || choices.length() == 0 {
        return error("Failed to process image: No response from AI.");
    }
    string? content = choices[0].message?.content;
    if content is () {
        return error("Failed to process image: Response content is empty.");
    }
    regexp:Groups? groups = regexp:findGroups(check regexp:fromString("```json\\s*([\\s\\S]*?)\\s*```"), content);
    if groups is () || groups.length() < 2 {
        return error("Failed to extract JSON data from response.");
    }
    regexp:Span? span = groups[1];
    if span is () {
        return error("Failed to extract JSON data from response.");
    }
    return span.substring().fromJsonString();
}

