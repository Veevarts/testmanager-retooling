import type {
  MyDayTaskState,
  MyDayTaskUrgency,
} from "@/features/csm/schemas/myDay";
import {
  Card,
  CardBody,
  Checkbox,
  CheckboxGroup,
  Select,
  SelectItem,
} from "@veevarts/design-system";

type MyDayFiltersProps = {
  accountFilter: string;
  accountOptions: Array<[string, string]>;
  formatLabel: (value: string) => string;
  onAccountFilterChange: (value: string) => void;
  onStateToggle: (state: MyDayTaskState) => void;
  onUrgencyFilterChange: (value: "all" | MyDayTaskUrgency) => void;
  stateFilters: MyDayTaskState[];
  stateOrder: MyDayTaskState[];
  urgencyFilter: "all" | MyDayTaskUrgency;
};

export const MyDayFilters = ({
  accountFilter,
  accountOptions,
  formatLabel,
  onAccountFilterChange,
  onStateToggle,
  onUrgencyFilterChange,
  stateFilters,
  stateOrder,
  urgencyFilter,
}: MyDayFiltersProps) => {
  const accountItems = [
    { key: "all", label: "All accounts" },
    ...accountOptions.map(([accountId, accountName]) => ({
      key: accountId,
      label: accountName,
    })),
  ];

  const urgencyItems: Array<{
    key: "all" | MyDayTaskUrgency;
    label: string;
  }> = [
    { key: "all", label: "All urgency levels" },
    { key: "critical", label: "Critical" },
    { key: "high", label: "High" },
    { key: "medium", label: "Medium" },
    { key: "low", label: "Low" },
  ];

  return (
    <Card
      radius="md"
      shadow="sm"
      className="mt-6 border border-default-200 bg-white"
    >
      <CardBody className="grid gap-4 p-5 lg:grid-cols-[1.2fr_1fr_1fr]">
        <CheckboxGroup
          label="State"
          orientation="horizontal"
          value={stateFilters}
          onValueChange={(values) => {
            const typedValues = values as MyDayTaskState[];
            if (typedValues.length === 0) return;

            const current = new Set(stateFilters);
            const next = new Set(typedValues);
            const toggledOff = stateOrder.find(
              (state) => current.has(state) && !next.has(state)
            );
            const toggledOn = stateOrder.find(
              (state) => next.has(state) && !current.has(state)
            );

            if (toggledOff) {
              onStateToggle(toggledOff);
              return;
            }

            if (toggledOn) {
              onStateToggle(toggledOn);
            }
          }}
          classNames={{
            label: "text-sm font-semibold text-default-800",
            wrapper: "mt-3 flex flex-wrap gap-2",
          }}
        >
          {stateOrder.map((state) => (
            <Checkbox
              key={state}
              value={state}
              radius="sm"
              classNames={{
                base: "m-0 rounded-xl border border-default-200 px-3 py-2 data-[selected=true]:border-[#E4571E]",
                label: "text-sm text-default-800",
                wrapper: "after:border-[#E4571E] before:border-default-300",
              }}
            >
              {formatLabel(state)}
            </Checkbox>
          ))}
        </CheckboxGroup>

        <Select
          aria-label="Filter by account"
          label="Account"
          labelPlacement="outside"
          radius="md"
          size="md"
          variant="bordered"
          selectedKeys={[accountFilter]}
          onSelectionChange={(keys) => {
            const [value] = Array.from(keys as Set<string>);
            if (value) {
              onAccountFilterChange(value);
            }
          }}
          className="mt-2"
          classNames={{
            label: "text-sm font-semibold text-default-800",
            value: "text-sm text-default-900",
          }}
          items={accountItems}
        >
          {(item) => <SelectItem key={item.key}>{item.label}</SelectItem>}
        </Select>

        <Select
          aria-label="Filter by urgency"
          label="Urgency"
          labelPlacement="outside"
          radius="md"
          size="md"
          variant="bordered"
          selectedKeys={[urgencyFilter]}
          onSelectionChange={(keys) => {
            const [value] = Array.from(keys as Set<string>);
            if (value) {
              onUrgencyFilterChange(value as "all" | MyDayTaskUrgency);
            }
          }}
          className="mt-2"
          classNames={{
            label: "text-sm font-semibold text-default-800",
            value: "text-sm text-default-900",
          }}
          items={urgencyItems}
        >
          {(item) => <SelectItem key={item.key}>{item.label}</SelectItem>}
        </Select>
      </CardBody>
    </Card>
  );
};
