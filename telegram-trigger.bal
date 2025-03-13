import ballerina/http;
import ballerina/log;
import ballerina/uuid;
import ballerinax/googleapis.drive;

configurable string botChatUrl = ?;
configurable string botFileUrl = ?;

configurable string refreshToken = ?;
configurable string clientId = ?;
configurable string clientSecret = ?;
configurable string refreshUrl = drive:REFRESH_URL;

final http:Client telegramClient = check new (botChatUrl);
final http:Client telegramFileClient = check new (botFileUrl);
final drive:Client driveClient = check new (driveConfig = {
    auth: {clientId, clientSecret, refreshUrl, refreshToken}
});

service /webhook on new http:Listener(8080) {
    isolated resource function post .(Update update) returns error? {
        string|error? query = constructQuery(update);
        if query is error {
            log:printError("Unable to construct query: ", query);
        }
        Message? message = update?.message;
        if query !is string || message is () {
            return;
        }
        log:printInfo(string `Constructed query ${query}`);
        string answer = check expenseClaimAgent->run(query, message.'from.id.toString());
        json reply = {chat_id: message.chat.id.toString(), text: answer};
        http:Response _ = check telegramClient->/sendMessage.post(reply);
    }
}

isolated function constructQuery(Update update) returns string|error? {
    Message? message = update?.message;
    if message is () {
        return;
    }
    string? text = message?.text;
    PhotoSize[]? photo = message?.photo;
    if photo is PhotoSize[] {
        // Retrieve the highest quality image
        string fileId = photo[photo.length() - 1].file_id;
        string publicImageUrl = check generatePublicImageUrl(fileId);
        return string `This is the recipt image url '${publicImageUrl}'`;
    }
    if text is string {
        return text;
    }
    return;
}

isolated function generatePublicImageUrl(string fileId) returns string|error {
    File file = check telegramClient->/getFile.get(file_id = fileId);
    string filePath = file.result.file_path;
    byte[] image = check telegramFileClient->/[filePath].get();
    string extention = re `\.`.split(filePath)[1];
    return uploadReciptToDrive(image, extention);
}

isolated function uploadReciptToDrive(byte[] image, string fileExtention) returns string|error {
    string reciptFolderId = "1ZzJ4rCZ4hSWySLAfyu6K_VjG4rdjhYI2";
    string fileName = string `${uuid:createRandomUuid()}.${fileExtention}`;
    drive:File file = check driveClient->uploadFileUsingByteArray(image, fileName, parentFolderId = reciptFolderId);
    file = check driveClient->getFile(check file.id.ensureType(), "webContentLink");
    return file.webContentLink.ensureType();
}
