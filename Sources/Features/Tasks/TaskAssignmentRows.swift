import SwiftUI

struct TaskAssignmentRows: View {
    let task: HiveTask
    @Environment(ProjectSession.self) private var session

    var body: some View {
        if let owner = task.ownerName {
            LabeledContent("Owner") {
                if let agentID = task.assigneeID {
                    Button(owner) {
                        session.showAgent(agentID)
                    }
                    .buttonStyle(.link)
                } else {
                    Text(owner)
                }
            }
        } else {
            LabeledContent("Owner", value: "Nobody")
        }
        if let expiry = task.leaseExpiresAt {
            LabeledContent("Claim Expires") {
                if task.isLeaseExpired {
                    Text("Expired")
                        .foregroundStyle(.orange)
                } else {
                    Text(expiry, format: .relative(presentation: .named))
                }
            }
        }
        LabeledContent("Can Be Claimed", value: task.isClaimable ? "Yes" : "No")
    }
}
