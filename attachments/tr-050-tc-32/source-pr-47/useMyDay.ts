import { getMyDay } from "@/features/csm/api/myDay";
import type { MyDayTask } from "@/features/csm/schemas/myDay";
import { useEffect, useState } from "react";

type UseMyDayResult = {
  tasks: MyDayTask[];
  isLoading: boolean;
  error: string | null;
};

export function useMyDay(): UseMyDayResult {
  const [tasks, setTasks] = useState<MyDayTask[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    const load = async () => {
      setIsLoading(true);
      setError(null);

      try {
        const response = await getMyDay();
        if (!active) return;
        setTasks(response.items);
      } catch (loadError) {
        if (!active) return;
        setError(
          loadError instanceof Error
            ? loadError.message
            : "Failed to load My Day tasks."
        );
      } finally {
        if (active) {
          setIsLoading(false);
        }
      }
    };

    void load();

    return () => {
      active = false;
    };
  }, []);

  return { tasks, isLoading, error };
}
