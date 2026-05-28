import { AppSkeleton } from "@/shared/components/AppSkeleton";
import { lazy, Suspense } from "react";
import { Navigate } from "react-router";

const MyDayPage = lazy(() =>
  import("./pages/MyDayPage").then((module) => ({
    default: module.MyDayPage,
  }))
);

const PortfolioPage = lazy(() =>
  import("./pages/PortfolioPage").then((module) => ({
    default: module.PortfolioPage,
  }))
);

const AccountsPage = lazy(() =>
  import("./pages/AccountsPage").then((module) => ({
    default: module.AccountsPage,
  }))
);

const ToolsAgentsPage = lazy(() =>
  import("./pages/ToolsAgentsPage").then((module) => ({
    default: module.ToolsAgentsPage,
  }))
);

const AccountDetailPage = lazy(() =>
  import("./pages/AccountDetailPage").then((module) => ({
    default: module.AccountDetailPage,
  }))
);

export const csmRoutes = [
  {
    path: "/csm",
    element: <Navigate to="/csm/my-day" replace />,
  },
  {
    path: "/csm/my-day",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <MyDayPage />
      </Suspense>
    ),
  },
  {
    path: "/csm/portfolio",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <PortfolioPage />
      </Suspense>
    ),
  },
  {
    path: "/csm/accounts",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <AccountsPage />
      </Suspense>
    ),
  },
  {
    path: "/csm/tools-agents",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <ToolsAgentsPage />
      </Suspense>
    ),
  },
  {
    path: "/csm/accounts/:accountId",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <AccountDetailPage />
      </Suspense>
    ),
  },
];
