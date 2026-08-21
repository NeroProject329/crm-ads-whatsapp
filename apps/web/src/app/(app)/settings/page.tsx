import { AdminPageGuard } from '@/components/auth/admin-page-guard';
import { SettingsManagement } from '@/components/f2/settings-management';

export default function SettingsPage() {
  return <AdminPageGuard><SettingsManagement /></AdminPageGuard>;
}
