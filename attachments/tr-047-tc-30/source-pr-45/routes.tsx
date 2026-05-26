import { lazy, Suspense } from "react";
import { AppSkeleton } from "@/shared/components/AppSkeleton";
import { Navigate, useParams } from "react-router";

const Clients = lazy(() =>
  import("./pages/Clients/ClientsPage").then((module) => ({
    default: module.Clients,
  }))
);

const ClientDetail = lazy(() =>
  import("./pages/ClientDetail/ClientDetailPage").then((module) => ({
    default: module.ClientDetail,
  }))
);

const ExecuteMigration = lazy(() =>
  import("./pages/ExecuteMigration/ExecuteMigrationPage").then((module) => ({
    default: module.ExecuteMigration,
  }))
);

const History = lazy(() =>
  import("./pages/History/HistoryPage").then((module) => ({
    default: module.History,
  }))
);

const PrepareMigration = lazy(() =>
  import("./pages/PrepareMigration/PrepareMigrationPage").then((module) => ({
    default: module.PrepareMigration,
  }))
);

const LegacyMigrationRedirect = ({
  resolveTo,
}: {
  resolveTo: (id: string) => string;
}) => {
  const { id = "" } = useParams<{ id: string }>();
  return <Navigate to={resolveTo(id)} replace />;
};

export const migrationRoutes = [
  {
    path: "/migration",
    element: <Navigate to="/migration/clients" replace />,
  },
  {
    path: "/migration/clients",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <Clients />
      </Suspense>
    ),
  },
  {
    path: "/migration/client-details/:id",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <ClientDetail />
      </Suspense>
    ),
  },
  {
    path: "/migration/execute-migration/:id",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <ExecuteMigration />
      </Suspense>
    ),
  },
  {
    path: "/migration/history/:id",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <History />
      </Suspense>
    ),
  },
  {
    path: "/migration/prepare-migration/:id",
    element: (
      <Suspense fallback={<AppSkeleton />}>
        <PrepareMigration />
      </Suspense>
    ),
  },
  {
    path: "/clients",
    element: <Navigate to="/migration/clients" replace />,
  },
  {
    path: "/client-details/:id",
    element: (
      <LegacyMigrationRedirect resolveTo={(id) => `/migration/client-details/${id}`} />
    ),
  },
  {
    path: "/execute-migration/:id",
    element: (
      <LegacyMigrationRedirect
        resolveTo={(id) => `/migration/execute-migration/${id}`}
      />
    ),
  },
  {
    path: "/history/:id",
    element: (
      <LegacyMigrationRedirect resolveTo={(id) => `/migration/history/${id}`} />
    ),
  },
  {
    path: "/prepare-migration/:id",
    element: (
      <LegacyMigrationRedirect
        resolveTo={(id) => `/migration/prepare-migration/${id}`}
      />
    ),
  },
];
