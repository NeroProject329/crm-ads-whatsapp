type PushSubscriptionState = Readonly<{
  id: string | null;
  token: string | null;
  optedIn: boolean;
}>;

type PushSubscriptionChangeEvent = Readonly<{
  previous: PushSubscriptionState;
  current: PushSubscriptionState;
}>;

type OneSignalSdk = {
  init(options: {
    appId: string;
    serviceWorkerPath: string;
    serviceWorkerParam: {
      scope: string;
    };
    autoResubscribe: boolean;
  }): Promise<void>;

  login(externalId: string): Promise<void>;

  logout(): Promise<void>;

  User: {
    onesignalId: string | null;

    PushSubscription: {
      id: string | null;

      token: string | null;

      optedIn: boolean;

      optIn(): Promise<void>;

      optOut(): Promise<void>;

      addEventListener(
        name: 'change',
        listener: (event: PushSubscriptionChangeEvent) => void,
      ): void;

      removeEventListener(
        name: 'change',
        listener: (event: PushSubscriptionChangeEvent) => void,
      ): void;
    };
  };

  Notifications: {
    isPushSupported(): boolean;

    permission: boolean;
  };
};

declare global {
  interface Window {
    OneSignalDeferred?: Array<(oneSignal: OneSignalSdk) => void | Promise<void>>;

    __crmOneSignalInitialized?: boolean;
  }
}

function withOneSignal(callback: (oneSignal: OneSignalSdk) => void | Promise<void>): void {
  window.OneSignalDeferred = window.OneSignalDeferred ?? [];

  window.OneSignalDeferred.push(callback);
}

export function initializeOneSignal(appId: string): void {
  if (typeof window === 'undefined') {
    return;
  }

  if (window.__crmOneSignalInitialized) {
    return;
  }

  window.__crmOneSignalInitialized = true;

  withOneSignal(async (oneSignal) => {
    await oneSignal.init({
      appId,

      serviceWorkerPath: '/push/onesignal/OneSignalSDKWorker.js',

      serviceWorkerParam: {
        scope: '/push/onesignal/',
      },

      autoResubscribe: true,
    });
  });
}

export type IdentifyPushUserInput = Readonly<{
  userId: string;
  accessToken: string;
  apiBaseUrl: string;
}>;

async function registerDevice(
  oneSignal: OneSignalSdk,
  input: IdentifyPushUserInput,
): Promise<void> {
  const subscriptionId = oneSignal.User.PushSubscription.id;

  if (!subscriptionId) {
    return;
  }

  await fetch(`${input.apiBaseUrl}/api/v1/push/devices`, {
    method: 'POST',

    headers: {
      Authorization: `Bearer ${input.accessToken}`,

      'Content-Type': 'application/json',
    },

    body: JSON.stringify({
      subscriptionId,

      oneSignalId: oneSignal.User.onesignalId,

      optedIn: oneSignal.User.PushSubscription.optedIn,

      platform: navigator.platform || null,

      browser: navigator.userAgent,

      deviceLabel: null,
    }),
  });
}

export function identifyPushUser(input: IdentifyPushUserInput): () => void {
  let cleanup: (() => void) | null = null;

  withOneSignal(async (oneSignal) => {
    await oneSignal.login(input.userId);

    await registerDevice(oneSignal, input);

    const listener = (event: PushSubscriptionChangeEvent) => {
      void event;

      void registerDevice(oneSignal, input);
    };

    oneSignal.User.PushSubscription.addEventListener('change', listener);

    cleanup = () => {
      oneSignal.User.PushSubscription.removeEventListener('change', listener);
    };
  });

  return () => {
    cleanup?.();
  };
}

export function requestPushPermission(): void {
  withOneSignal(async (oneSignal) => {
    if (!oneSignal.Notifications.isPushSupported()) {
      return;
    }

    await oneSignal.User.PushSubscription.optIn();
  });
}

export function optOutPush(): void {
  withOneSignal(async (oneSignal) => {
    await oneSignal.User.PushSubscription.optOut();
  });
}

export function detachPushUser(input: IdentifyPushUserInput): void {
  withOneSignal(async (oneSignal) => {
    const subscriptionId = oneSignal.User.PushSubscription.id;

    if (subscriptionId) {
      await fetch(`${input.apiBaseUrl}/api/v1/push/devices/${subscriptionId}`, {
        method: 'DELETE',

        headers: {
          Authorization: `Bearer ${input.accessToken}`,
        },
      });
    }

    await oneSignal.logout();
  });
}

export function isStandalonePwa(): boolean {
  if (typeof window === 'undefined') {
    return false;
  }

  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    ('standalone' in navigator &&
      Boolean(
        (
          navigator as Navigator & {
            standalone?: boolean;
          }
        ).standalone,
      ))
  );
}
