import { BrowserRouter, Route, Routes } from "react-router";
import { AppLayout } from "./components/layout/AppLayout";
import { RequireMultisigOwner } from "./features/admin/RequireMultisigOwner";
import { I18nProvider } from "./i18n/I18nProvider";
import { AdminPage } from "./pages/AdminPage";
import { AllowancesPage } from "./pages/AllowancesPage";
import { ComparePage } from "./pages/ComparePage";
import { IndexDetailPage } from "./pages/IndexDetailPage";
import { IndexListPage } from "./pages/IndexListPage";
import { LinkedWalletsPage } from "./pages/LinkedWalletsPage";
import { NotFoundPage } from "./pages/NotFoundPage";
import { NotificationsPage } from "./pages/NotificationsPage";
import { PortfolioPage } from "./pages/PortfolioPage";
import { DemoStateProvider } from "./session/DemoStateProvider";
import { SessionProvider } from "./session/SessionProvider";

// UI only, on demo data: wagmi, RainbowKit, SIWE and the API come later in phase 6.
export function App() {
  return (
    <I18nProvider>
      <BrowserRouter>
        <SessionProvider>
          <DemoStateProvider>
            <Routes>
              <Route element={<AppLayout />}>
                <Route index element={<IndexListPage />} />
                <Route path="index/:address" element={<IndexDetailPage />} />
                <Route path="compare" element={<ComparePage />} />
                <Route path="portfolio" element={<PortfolioPage />} />
                <Route path="portfolio/allowances" element={<AllowancesPage />} />
                <Route path="wallets" element={<LinkedWalletsPage />} />
                <Route path="notifications" element={<NotificationsPage />} />
                <Route
                  path="admin"
                  element={
                    <RequireMultisigOwner>
                      <AdminPage />
                    </RequireMultisigOwner>
                  }
                />
                <Route path="*" element={<NotFoundPage />} />
              </Route>
            </Routes>
          </DemoStateProvider>
        </SessionProvider>
      </BrowserRouter>
    </I18nProvider>
  );
}
