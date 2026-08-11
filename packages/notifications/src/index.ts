export type NotificationRequest = Readonly<{
  employeeId: string;
  eventType: string;
  title: string;
  body: string;
}>;

export interface NotificationProvider {
  send(request: NotificationRequest): Promise<void>;
}
