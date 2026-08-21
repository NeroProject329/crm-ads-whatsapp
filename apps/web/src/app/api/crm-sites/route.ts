import { forwardBackendRequest } from '@/lib/backend/forward';

const crmSitesBackendPath = '/sites';

export function GET(request: Request): Promise<Response> {
  return forwardBackendRequest(request, crmSitesBackendPath);
}

export function POST(request: Request): Promise<Response> {
  return forwardBackendRequest(request, crmSitesBackendPath);
}
