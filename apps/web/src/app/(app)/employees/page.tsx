import { AdminPageGuard } from '@/components/auth/admin-page-guard';
import { EmployeesManagement } from '@/components/f2/employees-management';

export default function EmployeesPage() {
  return <AdminPageGuard><EmployeesManagement /></AdminPageGuard>;
}
