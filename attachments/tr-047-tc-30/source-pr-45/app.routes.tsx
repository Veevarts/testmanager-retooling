import { csmRoutes } from "@/features/csm";
import { migrationRoutes } from "@/features/migration";
import { AppSkeleton } from "@/shared/components/AppSkeleton";
import { PostLoginRedirect } from "@/shared/auth/PostLoginRedirect";
import { ProtectedRoute } from "@/shared/auth/ProtectedRoute";
import { MainLayout } from "@/shared/layout/MainLayout";
import { Suspense } from "react";
import { createBrowserRouter, Outlet } from "react-router";
import { LoginPage, NotFoundPage } from "./lazyPages";
import { COGNITO_GROUPS } from "@/shared/hooks/useCognitoGroups";

const AuthenticatedRouteGroup = () => (
  <ProtectedRoute>
    <Outlet />
  </ProtectedRoute>
);

const UnauthorizedPage = () => (
  <div className="w-full px-4 py-6 sm:px-6 md:px-8">
    <h1 className="text-3xl font-bold">Unauthorized</h1>
    <p className="mt-3 text-default-600">
      Your account does not have access to this workspace.
    </p>
  </div>
);

export const router = createBrowserRouter(
  [
    {
      path: "/",
      element: (
        <Suspense fallback={<AppSkeleton />}>
          <LoginPage />
        </Suspense>
      ),
    },
    {
      element: <AuthenticatedRouteGroup />,
      children: [
        {
          path: "/post-login",
          element: <PostLoginRedirect />,
        },
        {
          path: "/unauthorized",
          element: <UnauthorizedPage />,
        },
      ],
    },
    {
      element: (
        <ProtectedRoute
          allowedGroups={[COGNITO_GROUPS.implementations, COGNITO_GROUPS.admin]}
        >
          <MainLayout />
        </ProtectedRoute>
      ),
      children: migrationRoutes,
    },
    {
      element: (
        <ProtectedRoute
          allowedGroups={[COGNITO_GROUPS.csm, COGNITO_GROUPS.admin]}
        >
          <MainLayout />
        </ProtectedRoute>
      ),
      children: csmRoutes,
    },
    {
      path: "*",
      element: (
        <Suspense fallback={<AppSkeleton />}>
          <NotFoundPage />
        </Suspense>
      ),
    },
  ]
);
