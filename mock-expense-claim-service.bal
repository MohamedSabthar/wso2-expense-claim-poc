import ballerina/http;
import ballerina/time;

public type ExpenseClaimRequest record {|
    string employeeEmail;
    string billDate;
    string currency;
    decimal amount;
    string jobNumber;
    string expenseType;
    string remarks;
    string receiptUrl;
|};

public type ExpenseClaimResponse record {|
    string status = "pending";
    string submittedDate;
|};

service / on new http:Listener(9090) {
    resource function post claims(ExpenseClaimRequest payload) returns ExpenseClaimResponse {
        return {submittedDate: time:utcToEmailString(time:utcNow())};
    }
}
