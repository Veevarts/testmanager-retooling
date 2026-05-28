import type { MyDayTask } from "@/features/csm/schemas/myDay";
import { Card, CardBody, Chip } from "@veevarts/design-system";

type MyDayTaskCardProps = {
  formatCardDueDate: (value: string) => string;
  formatLabel: (value: string) => string;
  isSelected: boolean;
  onClick: () => void;
  overdue: boolean;
  task: MyDayTask;
};

export const MyDayTaskCard = ({
  formatCardDueDate,
  formatLabel,
  isSelected,
  onClick,
  overdue,
  task,
}: MyDayTaskCardProps) => {
  return (
    <Card
      as="article"
      isPressable
      radius="md"
      shadow="sm"
      data-testid="my-day-task-card"
      data-overdue={overdue ? "true" : "false"}
      className={`cursor-pointer border transition hover:-translate-y-0.5 hover:shadow-md ${
        isSelected
          ? "border-[#E4571E] bg-white ring-2 ring-[#E4571E]/20"
          : overdue
            ? "border-rose-300 bg-rose-50/50"
            : "border-default-200 bg-white"
      }`}
      onPress={onClick}
    >
      <CardBody className="p-5">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <Chip
                radius="full"
                variant={overdue ? "bordered" : "flat"}
                className={`px-1 text-xs font-semibold uppercase tracking-[0.18em] ${
                  overdue
                    ? "border-rose-200 bg-white text-rose-700"
                    : "bg-default-100 text-default-700"
                }`}
              >
                {task.accountName}
              </Chip>
              <Chip
                radius="full"
                variant="solid"
                className="bg-slate-900 px-1 text-xs font-semibold uppercase tracking-[0.18em] text-white"
              >
                {formatLabel(task.state)}
              </Chip>
              <Chip
                radius="full"
                variant="solid"
                className="bg-[#E4571E] px-1 text-xs font-semibold uppercase tracking-[0.18em] text-white"
              >
                {formatLabel(task.urgency)}
              </Chip>
            </div>
            <h2 className="mt-4 text-xl font-bold text-default-900">
              {task.taskText}
            </h2>
            <p className="mt-3 text-sm leading-6 text-default-600">
              {task.justification}
            </p>
          </div>
          <Card
            as="dl"
            radius="md"
            shadow="none"
            className={`min-w-[140px] max-w-[160px] border px-4 py-3 text-sm ${
              overdue ? "border-rose-200 bg-white/80" : "border-transparent bg-default-50"
            }`}
          >
            <div className="flex flex-col gap-3">
              <div>
                <dt className="text-default-500">Due</dt>
                <dd
                  className={`font-semibold ${
                    overdue ? "text-rose-600" : "text-default-900"
                  }`}
                >
                  {formatCardDueDate(task.dueDate)}
                </dd>
              </div>
              <div>
                <dt className="text-default-500">Score</dt>
                <dd className="font-semibold text-default-900">{task.score}</dd>
              </div>
            </div>
          </Card>
        </div>
      </CardBody>
    </Card>
  );
};
