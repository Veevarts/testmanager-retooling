import { useMemo } from "react";
import { useAuth } from "react-oidc-context";

export const COGNITO_GROUPS = {
  admin: "admin",
  csm: "csm-team",
  implementations: "implementations-team",
} as const;

export type CognitoGroup =
  (typeof COGNITO_GROUPS)[keyof typeof COGNITO_GROUPS];

const normalizeGroups = (value: unknown): string[] => {
  if (Array.isArray(value)) {
    return value.filter((item): item is string => typeof item === "string");
  }

  if (typeof value === "string") {
    return [value];
  }

  return [];
};

const decodeJwtClaims = (token: string | undefined): Record<string, unknown> => {
  if (!token) {
    return {};
  }

  const [, payload] = token.split(".");
  if (!payload) {
    return {};
  }

  try {
    const normalizedPayload = payload.replace(/-/g, "+").replace(/_/g, "/");
    const decodedPayload = Uint8Array.from(atob(normalizedPayload), (char) =>
      char.charCodeAt(0)
    );
    return JSON.parse(
      new TextDecoder().decode(decodedPayload)
    ) as Record<string, unknown>;
  } catch {
    return {};
  }
};

export const useCognitoGroups = () => {
  const auth = useAuth();

  const groups = useMemo(() => {
    const profileGroups = auth.user?.profile?.["cognito:groups"];
    const idTokenGroups =
      decodeJwtClaims(auth.user?.id_token)["cognito:groups"];
    const accessTokenGroups =
      decodeJwtClaims(auth.user?.access_token)["cognito:groups"];
    const rawGroups = profileGroups ?? idTokenGroups ?? accessTokenGroups;

    return normalizeGroups(rawGroups);
  }, [auth.user?.access_token, auth.user?.id_token, auth.user?.profile]);

  const groupSet = useMemo(() => new Set(groups), [groups]);

  return {
    groups,
    hasGroup: (group: CognitoGroup) => groupSet.has(group),
    isAdmin: groupSet.has(COGNITO_GROUPS.admin),
    isCsm: groupSet.has(COGNITO_GROUPS.csm),
    isImplementations: groupSet.has(COGNITO_GROUPS.implementations),
  };
};
