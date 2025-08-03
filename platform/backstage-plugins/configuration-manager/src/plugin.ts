import {
  createPlugin,
  createRoutableExtension,
  createApiFactory,
  discoveryApiRef,
  fetchApiRef,
} from '@backstage/core-plugin-api';

import { rootRouteRef } from './routes';
import { configurationManagerApiRef, ConfigurationManagerApi } from './api';

export const configurationManagerPlugin = createPlugin({
  id: 'configuration-manager',
  routes: {
    root: rootRouteRef,
  },
  apis: [
    createApiFactory({
      api: configurationManagerApiRef,
      deps: {
        discoveryApi: discoveryApiRef,
        fetchApi: fetchApiRef,
      },
      factory: ({ discoveryApi, fetchApi }) =>
        new ConfigurationManagerApi({ discoveryApi, fetchApi }),
    }),
  ],
});

export const ConfigurationManagerPage = configurationManagerPlugin.provide(
  createRoutableExtension({
    name: 'ConfigurationManagerPage',
    component: () =>
      import('./components/ConfigurationManagerPage').then(m => m.ConfigurationManagerPage),
    mountPoint: rootRouteRef,
  }),
);