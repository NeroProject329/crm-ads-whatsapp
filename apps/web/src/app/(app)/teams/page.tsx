import { AdminPageGuard } from '@/components/auth/admin-page-guard';
import { TeamsManagement } from '@/components/f2/teams-management';

export default function TeamsPage() {
  return <AdminPageGuard><TeamsManagement /></AdminPageGuard>;
}
