import React, { useState, useEffect } from 'react';
import {
  Page,
  Header,
  Content,
  ContentHeader,
  HeaderLabel,
  SupportButton,
  Table,
  TableColumn,
  Progress,
  ResponseErrorPanel,
} from '@backstage/core-components';
import {
  Box,
  Button,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Fab,
  Grid,
  IconButton,
  Tab,
  Tabs,
  Typography,
  Card,
  CardContent,
  CardActions,
} from '@material-ui/core';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Delete as DeleteIcon,
  Settings as SettingsIcon,
  PlayArrow as DeployIcon,
  Compare as CompareIcon,
  History as HistoryIcon,
} from '@material-ui/icons';
import { useApi } from '@backstage/core-plugin-api';
import { configurationManagerApiRef, ApplicationConfiguration } from '../../api';
import { ConfigurationEditor } from '../ConfigurationEditor';
import { ConfigurationComparison } from '../ConfigurationComparison';
import { ConfigurationHistory } from '../ConfigurationHistory';
import { ConfigurationTemplates } from '../ConfigurationTemplates';

interface TabPanelProps {
  children?: React.ReactNode;
  index: number;
  value: number;
}

function TabPanel(props: TabPanelProps) {
  const { children, value, index, ...other } = props;

  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`simple-tabpanel-${index}`}
      aria-labelledby={`simple-tab-${index}`}
      {...other}
    >
      {value === index && (
        <Box p={3}>
          {children}
        </Box>
      )}
    </div>
  );
}

export const ConfigurationManagerPage = () => {
  const configApi = useApi(configurationManagerApiRef);
  const [configurations, setConfigurations] = useState<ApplicationConfiguration[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | undefined>();
  const [selectedConfig, setSelectedConfig] = useState<ApplicationConfiguration | undefined>();
  const [editorOpen, setEditorOpen] = useState(false);
  const [compareOpen, setCompareOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [templatesOpen, setTemplatesOpen] = useState(false);
  const [tabValue, setTabValue] = useState(0);

  useEffect(() => {
    loadConfigurations();
  }, [configApi]);

  const loadConfigurations = async () => {
    try {
      setLoading(true);
      const configs = await configApi.listConfigurations();
      setConfigurations(configs);
      setError(undefined);
    } catch (err) {
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  };

  const handleCreateNew = () => {
    setSelectedConfig(undefined);
    setEditorOpen(true);
  };

  const handleEdit = (config: ApplicationConfiguration) => {
    setSelectedConfig(config);
    setEditorOpen(true);
  };

  const handleDelete = async (config: ApplicationConfiguration) => {
    if (window.confirm(`Are you sure you want to delete ${config.metadata.name}?`)) {
      try {
        await configApi.deleteConfiguration(config.metadata.name, config.metadata.namespace);
        await loadConfigurations();
      } catch (err) {
        setError(err as Error);
      }
    }
  };

  const handleSave = async (config: ApplicationConfiguration) => {
    try {
      if (selectedConfig) {
        await configApi.updateConfiguration(config);
      } else {
        await configApi.createConfiguration(config);
      }
      await loadConfigurations();
      setEditorOpen(false);
      setSelectedConfig(undefined);
    } catch (err) {
      setError(err as Error);
    }
  };

  const handleCompare = (config: ApplicationConfiguration) => {
    setSelectedConfig(config);
    setCompareOpen(true);
  };

  const handleHistory = (config: ApplicationConfiguration) => {
    setSelectedConfig(config);
    setHistoryOpen(true);
  };

  const getEnvironmentChips = (config: ApplicationConfiguration) => {
    const environments = Object.keys(config.spec.environments || {});
    return environments.map(env => (
      <Chip 
        key={env} 
        label={env} 
        size="small" 
        style={{ margin: '2px' }}
        color={env === 'production' ? 'primary' : 'default'}
      />
    ));
  };

  const getStatusColor = (status: string) => {
    switch (status.toLowerCase()) {
      case 'running':
        return 'primary';
      case 'pending':
        return 'default';
      case 'error':
        return 'secondary';
      default:
        return 'default';
    }
  };

  const columns: TableColumn[] = [
    {
      title: 'Name',
      field: 'metadata.name',
      highlight: true,
      render: (rowData: ApplicationConfiguration) => (
        <Box>
          <Typography variant="subtitle2">
            {rowData.metadata.name}
          </Typography>
          <Typography variant="caption" color="textSecondary">
            {rowData.metadata.namespace}
          </Typography>
        </Box>
      ),
    },
    {
      title: 'Application',
      field: 'spec.application',
    },
    {
      title: 'Environments',
      field: 'environments',
      render: (rowData: ApplicationConfiguration) => (
        <Box>
          {getEnvironmentChips(rowData)}
        </Box>
      ),
    },
    {
      title: 'Status',
      field: 'status',
      render: () => (
        <Chip 
          label="Running" 
          size="small" 
          color="primary"
        />
      ),
    },
    {
      title: 'Last Modified',
      field: 'metadata.annotations["lastModified"]',
      render: () => (
        <Typography variant="caption">
          2 hours ago
        </Typography>
      ),
    },
    {
      title: 'Actions',
      field: 'actions',
      render: (rowData: ApplicationConfiguration) => (
        <Box>
          <IconButton 
            size="small" 
            onClick={() => handleEdit(rowData)}
            title="Edit Configuration"
          >
            <EditIcon />
          </IconButton>
          <IconButton 
            size="small" 
            onClick={() => handleCompare(rowData)}
            title="Compare Environments"
          >
            <CompareIcon />
          </IconButton>
          <IconButton 
            size="small" 
            onClick={() => handleHistory(rowData)}
            title="View History"
          >
            <HistoryIcon />
          </IconButton>
          <IconButton 
            size="small" 
            onClick={() => handleDelete(rowData)}
            title="Delete Configuration"
          >
            <DeleteIcon />
          </IconButton>
        </Box>
      ),
    },
  ];

  if (loading) {
    return <Progress />;
  }

  if (error) {
    return <ResponseErrorPanel error={error} />;
  }

  return (
    <Page themeId="tool">
      <Header title="Configuration Manager" subtitle="Manage application configurations across environments">
        <HeaderLabel label="Owner" value="Platform Team" />
        <HeaderLabel label="Lifecycle" value="Production" />
      </Header>
      <Content>
        <ContentHeader title="Application Configurations">
          <SupportButton>
            Manage application configurations, environment-specific settings, and deployment parameters through an intuitive UI.
          </SupportButton>
        </ContentHeader>

        <Box sx={{ borderBottom: 1, borderColor: 'divider', mb: 2 }}>
          <Tabs value={tabValue} onChange={(_, newValue) => setTabValue(newValue)}>
            <Tab label="Configurations" />
            <Tab label="Templates" />
            <Tab label="Monitoring" />
          </Tabs>
        </Box>

        <TabPanel value={tabValue} index={0}>
          <Box mb={2}>
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6} md={3}>
                <Card>
                  <CardContent>
                    <Typography color="textSecondary" gutterBottom>
                      Total Configurations
                    </Typography>
                    <Typography variant="h4">
                      {configurations.length}
                    </Typography>
                  </CardContent>
                </Card>
              </Grid>
              <Grid item xs={12} sm={6} md={3}>
                <Card>
                  <CardContent>
                    <Typography color="textSecondary" gutterBottom>
                      Active Deployments
                    </Typography>
                    <Typography variant="h4">
                      {configurations.length * 2} {/* Assuming 2 envs per config */}
                    </Typography>
                  </CardContent>
                </Card>
              </Grid>
              <Grid item xs={12} sm={6} md={3}>
                <Card>
                  <CardContent>
                    <Typography color="textSecondary" gutterBottom>
                      Environments
                    </Typography>
                    <Typography variant="h4">
                      3
                    </Typography>
                  </CardContent>
                </Card>
              </Grid>
              <Grid item xs={12} sm={6} md={3}>
                <Card>
                  <CardContent>
                    <Typography color="textSecondary" gutterBottom>
                      Templates Available
                    </Typography>
                    <Typography variant="h4">
                      8
                    </Typography>
                  </CardContent>
                </Card>
              </Grid>
            </Grid>
          </Box>

          <Table
            title="Application Configurations"
            options={{
              search: true,
              paging: true,
              pageSize: 10,
              actionsColumnIndex: -1,
            }}
            columns={columns}
            data={configurations}
            actions={[
              {
                icon: () => <AddIcon />,
                tooltip: 'Create New Configuration',
                isFreeAction: true,
                onClick: handleCreateNew,
              },
            ]}
          />

          <Fab
            color="primary"
            aria-label="add"
            style={{ position: 'fixed', bottom: 24, right: 24 }}
            onClick={handleCreateNew}
          >
            <AddIcon />
          </Fab>
        </TabPanel>

        <TabPanel value={tabValue} index={1}>
          <ConfigurationTemplates 
            onTemplateSelect={(template, appName, namespace) => {
              // Handle template selection
              console.log('Template selected:', template, appName, namespace);
            }}
          />
        </TabPanel>

        <TabPanel value={tabValue} index={2}>
          <Grid container spacing={3}>
            <Grid item xs={12} md={6}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Configuration Health
                  </Typography>
                  <Box mt={2}>
                    <Box display="flex" justifyContent="space-between" mb={1}>
                      <Typography variant="body2">Healthy</Typography>
                      <Typography variant="body2">85%</Typography>
                    </Box>
                    <Box bgcolor="success.main" height={8} borderRadius={4} />
                  </Box>
                </CardContent>
              </Card>
            </Grid>
            <Grid item xs={12} md={6}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Recent Changes
                  </Typography>
                  <Typography variant="body2" color="textSecondary">
                    12 configurations updated in the last 24 hours
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
          </Grid>
        </TabPanel>

        {/* Configuration Editor Dialog */}
        <Dialog 
          open={editorOpen} 
          onClose={() => setEditorOpen(false)}
          maxWidth="lg"
          fullWidth
        >
          <DialogTitle>
            {selectedConfig ? 'Edit Configuration' : 'Create New Configuration'}
          </DialogTitle>
          <DialogContent>
            <ConfigurationEditor
              configuration={selectedConfig}
              onSave={handleSave}
              onCancel={() => setEditorOpen(false)}
            />
          </DialogContent>
        </Dialog>

        {/* Configuration Comparison Dialog */}
        <Dialog 
          open={compareOpen} 
          onClose={() => setCompareOpen(false)}
          maxWidth="lg"
          fullWidth
        >
          <DialogTitle>Compare Environments</DialogTitle>
          <DialogContent>
            {selectedConfig && (
              <ConfigurationComparison
                configuration={selectedConfig}
                onClose={() => setCompareOpen(false)}
              />
            )}
          </DialogContent>
        </Dialog>

        {/* Configuration History Dialog */}
        <Dialog 
          open={historyOpen} 
          onClose={() => setHistoryOpen(false)}
          maxWidth="md"
          fullWidth
        >
          <DialogTitle>Configuration History</DialogTitle>
          <DialogContent>
            {selectedConfig && (
              <ConfigurationHistory
                configuration={selectedConfig}
                onClose={() => setHistoryOpen(false)}
              />
            )}
          </DialogContent>
        </Dialog>
      </Content>
    </Page>
  );
};