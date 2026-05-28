import type { MyDayResponse } from "@/features/csm/schemas/myDay";

export const myDayFixture: MyDayResponse = {
  items: [
    {
      id: "task-100",
      accountId: "account-vizcaya",
      accountName: "Vizcaya Museum & Gardens",
      taskText: "Approve next-week executive check-in prep",
      justification:
        "Leadership asked for a consolidated brief after two unresolved escalations.",
      dueDate: "2026-05-23",
      state: "suggested",
      urgency: "critical",
      score: 98,
    },
    {
      id: "task-101",
      accountId: "account-lotusland",
      accountName: "Lotusland",
      taskText: "Draft renewal talking points for board review",
      justification:
        "The account health score dropped and the renewal deck is due this week.",
      dueDate: "2026-05-24",
      state: "new",
      urgency: "critical",
      score: 87,
    },
    {
      id: "task-102",
      accountId: "account-vizcaya",
      accountName: "Vizcaya Museum & Gardens",
      taskText: "Confirm training follow-up owners",
      justification:
        "The last enablement session created open actions across ticketing and CRM teams.",
      dueDate: "2026-05-24",
      state: "in-progress",
      urgency: "high",
      score: 95,
    },
    {
      id: "task-103",
      accountId: "account-nasher",
      accountName: "Nasher Museum",
      taskText: "Review campaign import blockers",
      justification:
        "A migration dependency is putting the customer timeline at risk.",
      dueDate: "2026-05-25",
      state: "suggested",
      urgency: "high",
      score: 91,
    },
    {
      id: "task-104",
      accountId: "account-lotusland",
      accountName: "Lotusland",
      taskText: "Prepare adoption summary for Monday sync",
      justification:
        "Product usage dipped in memberships and the account team asked for a CSM readout.",
      dueDate: "2026-05-28",
      state: "new",
      urgency: "medium",
      score: 84,
    },
    {
      id: "task-105",
      accountId: "account-kiewit",
      accountName: "Kiewit Luminarium",
      taskText: "Triage box office reconciliation questions",
      justification:
        "Finance requested answers before they close the weekly variance review.",
      dueDate: "2026-05-29",
      state: "suggested",
      urgency: "medium",
      score: 80,
    },
  ],
};
