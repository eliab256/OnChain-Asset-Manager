import { useState } from "react";
import { Link, NavLink } from "react-router";
import { useI18n } from "../../i18n/context";
import { useSession } from "../../session/context";
import { Icon } from "../ui/Icon";
import { cx } from "../ui/cx";
import { AccountMenu } from "./AccountMenu";
import { NotificationBell } from "./NotificationBell";
import { ChainSelect, LanguageSelect } from "./Selectors";

export function Header() {
  const { t } = useI18n();
  const { isAdmin, signedIn } = useSession();
  const [menuOpen, setMenuOpen] = useState(false);

  // The admin link exists only for a signed-in MultiSig owner.
  const links = [
    { to: "/", label: t.nav.indexes, end: true },
    { to: "/compare", label: t.nav.compare, end: false },
    { to: "/portfolio", label: t.nav.portfolio, end: false },
    ...(isAdmin ? [{ to: "/admin", label: t.nav.admin, end: false }] : []),
  ];

  const desktopLink = ({ isActive }: { isActive: boolean }) =>
    cx("rounded-lg px-3 py-2 text-sm font-semibold transition-colors", isActive ? "bg-navy-800 text-white" : "text-navy-300 hover:text-white");
  const mobileLink = ({ isActive }: { isActive: boolean }) =>
    cx("block rounded-lg px-3 py-3 text-base font-semibold", isActive ? "bg-navy-800 text-white" : "text-navy-200");

  return (
    <header className="sticky top-0 z-30 bg-navy-900 text-white shadow-md">
      <div className="mx-auto flex h-16 max-w-7xl items-center gap-3 px-4 sm:px-6">
        <button
          type="button"
          className="-ml-2 rounded-lg p-2 text-navy-200 hover:bg-navy-800 lg:hidden"
          onClick={() => setMenuOpen((o) => !o)}
          aria-expanded={menuOpen}
          aria-controls="mobile-menu"
          aria-label={menuOpen ? t.nav.closeMenu : t.nav.menu}
        >
          <Icon name={menuOpen ? "close" : "menu"} />
        </button>

        <Link to="/" className="flex items-center gap-2 font-bold" onClick={() => setMenuOpen(false)}>
          <span className="flex size-8 items-center justify-center rounded-lg bg-brand-600 text-xs tracking-tight">{t.common.appShort}</span>
          <span className="hidden sm:inline">{t.common.appName}</span>
        </Link>

        <nav className="ml-4 hidden items-center gap-1 lg:flex">
          {links.map((l) => (
            <NavLink key={l.to} to={l.to} end={l.end} className={desktopLink}>
              {l.label}
            </NavLink>
          ))}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          <ChainSelect className="hidden w-44 md:block" />
          <LanguageSelect className="hidden w-28 md:block" />
          {signedIn && <NotificationBell />}
          <AccountMenu />
        </div>
      </div>

      {menuOpen && (
        <div id="mobile-menu" className="border-t border-navy-800 px-4 pt-2 pb-4 lg:hidden">
          <nav className="flex flex-col">
            {links.map((l) => (
              <NavLink key={l.to} to={l.to} end={l.end} className={mobileLink} onClick={() => setMenuOpen(false)}>
                {l.label}
              </NavLink>
            ))}
          </nav>
          <div className="mt-3 grid grid-cols-2 gap-3 md:hidden">
            <div>
              <div className="mb-1 text-xs text-navy-300">{t.nav.network}</div>
              <ChainSelect />
            </div>
            <div>
              <div className="mb-1 text-xs text-navy-300">{t.nav.language}</div>
              <LanguageSelect />
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
