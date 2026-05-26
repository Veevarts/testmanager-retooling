import {
  clearAuthIntent,
  getAuthLoadingCopy,
} from "@/shared/auth/auth-intent";
import { Spinner } from "@/shared/components/Spinner/Spinner";
import {
  type CognitoGroup,
  useCognitoGroups,
} from "@/shared/hooks/useCognitoGroups";
import { useEffect } from "react";
import { useAuth } from "react-oidc-context";
import { Navigate } from "react-router";

interface ProtectedRouteProps {
  children: React.ReactNode;
  allowedGroups?: CognitoGroup[];
}

export const ProtectedRoute = ({
  children,
  allowedGroups,
}: ProtectedRouteProps) => {
  const auth = useAuth();
  const { hasGroup } = useCognitoGroups();
  const loadingCopy = getAuthLoadingCopy();

  useEffect(() => {
    if (!auth.isLoading) {
      clearAuthIntent();
    }
  }, [auth.isLoading]);

  if (auth.isLoading) {
    return (
      <div className="flex min-h-screen w-full items-center justify-center bg-black px-6">
        <div className="flex w-full max-w-md flex-col items-center gap-5 rounded-3xl bg-white/95 px-8 py-10 text-center shadow-2xl">
          <Spinner />
          <div className="space-y-2">
            <p className="text-2xl font-bold text-black">{loadingCopy.title}</p>
            <p className="text-sm text-default-600">{loadingCopy.description}</p>
          </div>
        </div>
      </div>
    );
  }

  if (auth.error) {
    return <div>Encountering error... {auth.error.message}</div>;
  }

  if (!auth.isAuthenticated) {
    return <Navigate to="/" replace />;
  }

  if (allowedGroups?.length && !allowedGroups.some((group) => hasGroup(group))) {
    return <Navigate to="/unauthorized" replace />;
  }

  return <>{children}</>;
};
