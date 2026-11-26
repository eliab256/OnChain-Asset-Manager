import type { ButtonHTMLAttributes, ReactNode } from "react";
import { Link } from "react-router";
import { cx } from "./cx";

type Variant = "primary" | "secondary" | "ghost" | "warning" | "dark";
type Size = "sm" | "md" | "lg";

const VARIANTS: Record<Variant, string> = {
  primary: "bg-brand-600 text-white hover:bg-brand-700 disabled:bg-navy-200 disabled:text-navy-500",
  secondary: "border border-navy-200 bg-white text-navy-900 hover:border-brand-600 hover:text-brand-700 disabled:text-navy-300",
  ghost: "text-navy-700 hover:bg-navy-100 disabled:text-navy-300",
  warning: "border border-amber-500 bg-amber-50 text-amber-700 hover:bg-amber-100 disabled:opacity-50",
  dark: "bg-navy-800 text-white hover:bg-navy-700 disabled:opacity-50",
};

const SIZES: Record<Size, string> = {
  sm: "h-8 px-3 text-xs",
  md: "h-10 px-4 text-sm",
  lg: "h-12 px-5 text-base",
};

function classes(variant: Variant, size: Size, block: boolean, className?: string) {
  return cx(
    "inline-flex items-center justify-center gap-2 rounded-lg font-semibold whitespace-nowrap transition-colors disabled:cursor-not-allowed",
    VARIANTS[variant],
    SIZES[size],
    block && "w-full",
    className,
  );
}

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  block?: boolean;
}

export function Button({ variant = "primary", size = "md", block = false, className, type = "button", ...rest }: ButtonProps) {
  return <button type={type} className={classes(variant, size, block, className)} {...rest} />;
}

interface ButtonLinkProps {
  to: string;
  children: ReactNode;
  variant?: Variant;
  size?: Size;
  block?: boolean;
  className?: string;
}

export function ButtonLink({ to, children, variant = "primary", size = "md", block = false, className }: ButtonLinkProps) {
  return (
    <Link to={to} className={classes(variant, size, block, className)}>
      {children}
    </Link>
  );
}
