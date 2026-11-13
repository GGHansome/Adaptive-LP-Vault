import type { ReactNode } from 'react';
export type Field = {
  name: string;
  label: string;
  initial?: string;
  placeholder?: string;
  hint?: string;
  type?: 'number' | 'address';
};
export type FormValues = Record<string, string>;
export type ActionFormProps = {
  title: string;
  description?: string;
  fields: Field[];
  submit: string;
  onSubmit: (values: FormValues) => Promise<unknown>;
  disabled?: boolean;
  busy?: boolean;
  danger?: boolean;
  confirm?: string;
  notice?: string;
  children?: ReactNode;
  onValuesChange?: (values: FormValues) => void;
};
