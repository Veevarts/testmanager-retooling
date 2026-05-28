import { z } from "zod";

export const myDayTaskStateSchema = z.enum([
  "suggested",
  "new",
  "in-progress",
]);

export const myDayTaskUrgencySchema = z.enum([
  "critical",
  "high",
  "medium",
  "low",
]);

export const myDayTaskSchema = z.object({
  id: z.string().min(1),
  accountId: z.string().min(1),
  accountName: z.string().min(1),
  taskText: z.string().min(1),
  justification: z.string().min(1),
  dueDate: z.string().min(1),
  state: myDayTaskStateSchema,
  urgency: myDayTaskUrgencySchema,
  score: z.number(),
});

export const myDayResponseSchema = z.object({
  items: z.array(myDayTaskSchema),
});

export type MyDayTaskState = z.infer<typeof myDayTaskStateSchema>;
export type MyDayTaskUrgency = z.infer<typeof myDayTaskUrgencySchema>;
export type MyDayTask = z.infer<typeof myDayTaskSchema>;
export type MyDayResponse = z.infer<typeof myDayResponseSchema>;
