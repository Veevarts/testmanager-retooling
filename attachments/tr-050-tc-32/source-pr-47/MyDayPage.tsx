import {
  MyDayFilters,
  MyDayTaskCard,
  MyDayTaskDetail,
  WorkspacePageSection,
} from "@/features/csm/components";
import { useMyDay } from "@/features/csm/hooks/useMyDay";
import { FeedbackBanner } from "@/shared/components/FeedbackBanner";
import type {
  MyDayTask,
  MyDayTaskState,
  MyDayTaskUrgency,
} from "@/features/csm/schemas/myDay";
import { useMemo, useState } from "react";

const urgencyRank: Record<MyDayTaskUrgency, number> = {
  critical: 4,
  high: 3,
  medium: 2,
  low: 1,
};

const stateOrder: MyDayTaskState[] = ["suggested", "new", "in-progress"];

const formatLabel = (value: string) =>
  value
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");

const formatCardDueDate = (value: string) => {
  const [year, month, day] = value.split("-");
  const parsedYear = Number(year);
  const parsedMonth = Number(month);
  const parsedDay = Number(day);

  if (
    !year ||
    !month ||
    !day ||
    Number.isNaN(parsedYear) ||
    Number.isNaN(parsedMonth) ||
    Number.isNaN(parsedDay)
  ) {
    return value;
  }

  const monthLabel = new Intl.DateTimeFormat("en-GB", {
    month: "short",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(parsedYear, parsedMonth - 1, 1)));

  return `${String(parsedDay).padStart(2, "0")} ${monthLabel} ${parsedYear}`;
};

const parseDateOnlyValue = (value: string) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) {
    return null;
  }

  const [, year, month, day] = match;
  return Number(year) * 10_000 + Number(month) * 100 + Number(day);
};

const compareDateOnlyValues = (left: string, right: string) => {
  const parsedLeft = parseDateOnlyValue(left);
  const parsedRight = parseDateOnlyValue(right);

  if (parsedLeft !== null && parsedRight !== null) {
    return parsedLeft - parsedRight;
  }

  return left.localeCompare(right);
};

const getTodayDateKey = () => {
  const today = new Date();
  const year = today.getFullYear();
  const month = String(today.getMonth() + 1).padStart(2, "0");
  const day = String(today.getDate()).padStart(2, "0");

  return `${year}-${month}-${day}`;
};

const compareTasks = (left: MyDayTask, right: MyDayTask) => {
  const urgencyDelta = urgencyRank[right.urgency] - urgencyRank[left.urgency];
  if (urgencyDelta !== 0) return urgencyDelta;

  const dueDateDelta = compareDateOnlyValues(left.dueDate, right.dueDate);
  if (dueDateDelta !== 0) return dueDateDelta;

  return right.score - left.score;
};

const isOverdue = (task: MyDayTask) => {
  return compareDateOnlyValues(task.dueDate, getTodayDateKey()) < 0;
};

export const MyDayPage = () => {
  const { tasks, isLoading, error } = useMyDay();
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  const [stateFilters, setStateFilters] = useState<MyDayTaskState[]>(stateOrder);
  const [accountFilter, setAccountFilter] = useState("all");
  const [urgencyFilter, setUrgencyFilter] = useState<"all" | MyDayTaskUrgency>(
    "all"
  );
  const [isEditingTask, setIsEditingTask] = useState(false);
  const [draftTaskText, setDraftTaskText] = useState("");
  const [draftJustification, setDraftJustification] = useState("");
  const [draftDueDate, setDraftDueDate] = useState("");
  const [draftState, setDraftState] = useState<MyDayTaskState>("suggested");
  const [draftUrgency, setDraftUrgency] =
    useState<MyDayTaskUrgency>("medium");
  const [feedback, setFeedback] = useState<string | null>(null);
  const [taskOverrides, setTaskOverrides] = useState<Record<string, MyDayTask>>(
    {}
  );
  const [removedTaskIds, setRemovedTaskIds] = useState<string[]>([]);

  const effectiveTasks = useMemo(() => {
    return tasks
      .filter((task) => !removedTaskIds.includes(task.id))
      .map((task) => taskOverrides[task.id] ?? task)
      .sort(compareTasks);
  }, [removedTaskIds, taskOverrides, tasks]);

  const accountOptions = useMemo(
    () =>
      Array.from(
        new Map(
          effectiveTasks.map((task) => [task.accountId, task.accountName])
        ).entries()
      ),
    [effectiveTasks]
  );

  const filteredTasks = useMemo(
    () =>
      effectiveTasks.filter((task) => {
        const matchesState = stateFilters.includes(task.state);
        const matchesAccount =
          accountFilter === "all" || task.accountId === accountFilter;
        const matchesUrgency =
          urgencyFilter === "all" || task.urgency === urgencyFilter;

        return matchesState && matchesAccount && matchesUrgency;
      }),
    [accountFilter, effectiveTasks, stateFilters, urgencyFilter]
  );

  const selectedTask = useMemo(() => {
    return (
      filteredTasks.find((task) => task.id === selectedTaskId) ??
      effectiveTasks.find((task) => task.id === selectedTaskId) ??
      null
    );
  }, [effectiveTasks, filteredTasks, selectedTaskId]);

  const updateTask = (taskId: string, updater: (task: MyDayTask) => MyDayTask) => {
    setTaskOverrides((current) => {
      const sourceTask =
        current[taskId] ?? tasks.find((task) => task.id === taskId);
      if (!sourceTask) return current;

      return {
        ...current,
        [taskId]: updater(sourceTask),
      };
    });
  };

  const removeTask = (taskId: string) => {
    setRemovedTaskIds((current) => [...current, taskId]);

    if (selectedTaskId === taskId) {
      setSelectedTaskId(null);
    }
  };

  const handleTaskClick = (task: MyDayTask) => {
    setSelectedTaskId(task.id);
    setIsEditingTask(false);
    setDraftTaskText(task.taskText);
    setDraftJustification(task.justification);
    setDraftDueDate(task.dueDate);
    setDraftState(task.state);
    setDraftUrgency(task.urgency);
  };

  const handleStateToggle = (state: MyDayTaskState) => {
    setStateFilters((current) => {
      if (current.includes(state)) {
        const next = current.filter((entry) => entry !== state);
        return next.length > 0 ? next : current;
      }

      return [...current, state];
    });
  };

  const handleApprove = (task: MyDayTask) => {
    const nextState =
      task.state === "suggested" ? ("new" as const) : task.state;

    updateTask(task.id, (currentTask) => ({
      ...currentTask,
      state: nextState,
    }));
    if (selectedTaskId === task.id) {
      setDraftState(nextState);
    }
    setFeedback(
      task.state === "suggested"
        ? `Approved ${task.accountName} task and moved it into the active queue.`
        : `${task.accountName} task is already approved.`
    );
  };

  const handleReject = (task: MyDayTask) => {
    removeTask(task.id);
    setFeedback(`Rejected ${task.accountName} task from the mock queue.`);
  };

  const handleMarkInProgress = (task: MyDayTask) => {
    updateTask(task.id, (currentTask) => ({
      ...currentTask,
      state: "in-progress",
    }));
    if (selectedTaskId === task.id) {
      setDraftState("in-progress");
    }
    setFeedback(`Marked ${task.accountName} task as In Progress.`);
  };

  const handleSaveEdit = () => {
    if (
      !selectedTask ||
      !draftTaskText.trim() ||
      !draftJustification.trim() ||
      !draftDueDate
    ) {
      return;
    }

    updateTask(selectedTask.id, (currentTask) => ({
      ...currentTask,
      taskText: draftTaskText.trim(),
      justification: draftJustification.trim(),
      dueDate: draftDueDate,
      state: draftState,
      urgency: draftUrgency,
    }));
    setIsEditingTask(false);
    setFeedback(`Saved changes for ${selectedTask.accountName}.`);
  };

  const handleEditToggle = () => {
    if (!selectedTask) return;

    if (isEditingTask) {
      handleSaveEdit();
      return;
    }

    setDraftTaskText(selectedTask.taskText);
    setDraftJustification(selectedTask.justification);
    setDraftDueDate(selectedTask.dueDate);
    setDraftState(selectedTask.state);
    setDraftUrgency(selectedTask.urgency);
    setIsEditingTask(true);
  };

  return (
    <div className="w-full px-4 py-6 sm:px-6 md:px-8">
      <WorkspacePageSection
        eyebrow="CSM Control Tower"
        title="My Day"
        description="Prioritized cross-account actions for the day. This phase stays mock-only, but it already uses the planned `GET /api/csm/my-day` response shape so the later data swap stays surgical."
        variant="hero"
      />

      <MyDayFilters
        accountFilter={accountFilter}
        accountOptions={accountOptions}
        formatLabel={formatLabel}
        onAccountFilterChange={setAccountFilter}
        onStateToggle={handleStateToggle}
        onUrgencyFilterChange={setUrgencyFilter}
        stateFilters={stateFilters}
        stateOrder={stateOrder}
        urgencyFilter={urgencyFilter}
      />

      {feedback ? (
        <FeedbackBanner
          dismissLabel="Dismiss feedback"
          message={feedback}
          onDismiss={() => setFeedback(null)}
        />
      ) : null}

      {error ? (
        <div className="mt-6 rounded-[0.7rem] border border-danger-200 bg-danger-50 px-4 py-3 text-danger-700">
          {error}
        </div>
      ) : null}

      {isLoading ? (
        <div className="mt-6 rounded-[0.7rem] border border-default-200 bg-white p-8 shadow-sm">
          <p className="text-default-500">Loading My Day tasks...</p>
        </div>
      ) : (
        <div className="mt-6 grid gap-6 xl:grid-cols-[1.7fr_1fr]">
          <section className="space-y-4">
            {filteredTasks.length === 0 ? (
              <div className="rounded-[0.7rem] border border-dashed border-emerald-300 bg-emerald-50 px-6 py-12 text-center shadow-sm">
                <p className="text-xs font-semibold uppercase tracking-[0.28em] text-emerald-700">
                  Queue clear
                </p>
                <h2 className="mt-3 text-3xl font-black text-emerald-900">
                  All caught up — no pending actions
                </h2>
                <p className="mt-3 text-sm text-emerald-800">
                  Change the quick filters if you want to inspect archived mock work.
                </p>
              </div>
            ) : (
              filteredTasks.map((task) => {
                const overdue = isOverdue(task);

                return (
                  <MyDayTaskCard
                    key={task.id}
                    formatCardDueDate={formatCardDueDate}
                    formatLabel={formatLabel}
                    isSelected={selectedTaskId === task.id}
                    onClick={() => handleTaskClick(task)}
                    overdue={overdue}
                    task={task}
                  />
                );
              })
            )}
          </section>

          <aside className="rounded-[0.7rem] border border-default-200 bg-white p-5 shadow-sm">
            {selectedTask ? (
              <MyDayTaskDetail
                draftDueDate={draftDueDate}
                draftJustification={draftJustification}
                draftState={draftState}
                draftTaskText={draftTaskText}
                draftUrgency={draftUrgency}
                formatLabel={formatLabel}
                isEditingTask={isEditingTask}
                onApprove={() => handleApprove(selectedTask)}
                onDraftDueDateChange={setDraftDueDate}
                onDraftJustificationChange={setDraftJustification}
                onDraftStateChange={setDraftState}
                onDraftTaskTextChange={setDraftTaskText}
                onDraftUrgencyChange={setDraftUrgency}
                onEditToggle={handleEditToggle}
                onMarkInProgress={() => handleMarkInProgress(selectedTask)}
                onReject={() => handleReject(selectedTask)}
                selectedTask={selectedTask}
                stateOrder={stateOrder}
                urgencyOptions={Object.keys(urgencyRank) as MyDayTaskUrgency[]}
              />
            ) : (
              <div className="flex h-full min-h-72 flex-col items-center justify-center rounded-[0.7rem] border border-dashed border-default-200 bg-default-50 px-6 text-center">
                <p className="text-xs font-semibold uppercase tracking-[0.28em] text-default-500">
                  No task selected
                </p>
                <h2 className="mt-3 text-2xl font-black text-default-900">
                  Pick an item from the queue
                </h2>
                <p className="mt-3 text-sm text-default-600">
                  Selecting a task opens inline detail here without leaving the control
                  tower.
                </p>
              </div>
            )}
          </aside>
        </div>
      )}
    </div>
  );
};
