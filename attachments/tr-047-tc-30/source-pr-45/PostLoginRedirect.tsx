import { COGNITO_GROUPS, useCognitoGroups } from "@/shared/hooks/useCognitoGroups";
import { useAuth } from "react-oidc-context";
import { Navigate } from "react-router";

export const PostLoginRedirect = () => {
  useAuth();
  const { hasGroup, isAdmin } = useCognitoGroups();

  if (isAdmin || hasGroup(COGNITO_GROUPS.csm)) {
    return <Navigate to="/csm/my-day" replace />;
  }

  if (hasGroup(COGNITO_GROUPS.implementations)) {
    return <Navigate to="/migration" replace />;
  }

  return <Navigate to="/unauthorized" replace />;
};
