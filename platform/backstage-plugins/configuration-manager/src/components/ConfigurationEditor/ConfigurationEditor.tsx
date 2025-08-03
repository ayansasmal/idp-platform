import React, { useState, useEffect } from 'react';
import {
  Box,
  Button,
  FormControl,
  FormControlLabel,
  Grid,
  InputLabel,
  MenuItem,
  Paper,
  Select,
  Switch,
  Tab,
  Tabs,
  TextField,
  Typography,
  Accordion,
  AccordionSummary,
  AccordionDetails,
  Chip,
  IconButton,
} from '@material-ui/core';
import {
  ExpandMore as ExpandMoreIcon,
  Add as AddIcon,
  Delete as DeleteIcon,
  Visibility as PreviewIcon,
  CheckCircle as ValidateIcon,
} from '@material-ui/icons';
import { CodeSnippet } from '@backstage/core-components';
import { useApi } from '@backstage/core-plugin-api';
import { ApplicationConfiguration, configurationManagerApiRef } from '../../api';
import * as yaml from 'yaml';

interface ConfigurationEditorProps {
  configuration?: ApplicationConfiguration;
  onSave: (config: ApplicationConfiguration) => void;
  onCancel: () => void;
}

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
      id={`editor-tabpanel-${index}`}
      {...other}
    >
      {value === index && <Box>{children}</Box>}
    </div>
  );
}

export const ConfigurationEditor: React.FC<ConfigurationEditorProps> = ({
  configuration,
  onSave,
  onCancel,
}) => {
  const configApi = useApi(configurationManagerApiRef);
  const [config, setConfig] = useState<ApplicationConfiguration>(
    configuration || {
      apiVersion: 'platform.idp/v1alpha1',
      kind: 'ApplicationConfiguration',
      metadata: {
        name: '',
        namespace: 'default',
      },
      spec: {
        application: '',
        environments: {},
      },
    }
  );
  const [tabValue, setTabValue] = useState(0);
  const [validation, setValidation] = useState<any>({ valid: true, errors: [], warnings: [] });
  const [preview, setPreview] = useState<string>('');
  const [showPreview, setShowPreview] = useState(false);

  const environments = ['development', 'staging', 'production'];
  const resourceSizes = {
    small: { cpu: '100m', memory: '128Mi' },
    medium: { cpu: '500m', memory: '512Mi' },
    large: { cpu: '1000m', memory: '1Gi' },
  };

  useEffect(() => {
    validateConfiguration();
  }, [config]);

  const validateConfiguration = async () => {
    try {
      const result = await configApi.validateConfiguration(config);
      setValidation(result);
    } catch (error) {
      console.error('Validation failed:', error);
    }
  };

  const generatePreview = async () => {
    try {
      const previewText = await configApi.previewConfiguration(config);
      setPreview(previewText);
      setShowPreview(true);
    } catch (error) {
      console.error('Preview generation failed:', error);
    }
  };

  const updateMetadata = (field: string, value: string) => {
    setConfig(prev => ({
      ...prev,
      metadata: {
        ...prev.metadata,
        [field]: value,
      },
    }));
  };

  const addEnvironment = (envName: string) => {
    if (!config.spec.environments[envName]) {
      setConfig(prev => ({
        ...prev,
        spec: {
          ...prev.spec,
          environments: {
            ...prev.spec.environments,
            [envName]: {
              replicas: 1,
              resources: {
                requests: { cpu: '100m', memory: '128Mi' },
                limits: { cpu: '500m', memory: '512Mi' },
              },
              environment: {},
            },
          },
        },
      }));
    }
  };

  const removeEnvironment = (envName: string) => {
    const newEnvs = { ...config.spec.environments };
    delete newEnvs[envName];
    setConfig(prev => ({
      ...prev,
      spec: {
        ...prev.spec,
        environments: newEnvs,
      },
    }));
  };

  const updateEnvironment = (envName: string, field: string, value: any) => {
    setConfig(prev => ({
      ...prev,
      spec: {
        ...prev.spec,
        environments: {
          ...prev.spec.environments,
          [envName]: {
            ...prev.spec.environments[envName],
            [field]: value,
          },
        },
      },
    }));
  };

  const updateResourceSize = (envName: string, size: 'small' | 'medium' | 'large') => {
    const resources = resourceSizes[size];
    updateEnvironment(envName, 'resources', {
      requests: resources,
      limits: { cpu: `${parseInt(resources.cpu) * 2}m`, memory: resources.memory },
    });
  };

  const addEnvironmentVariable = (envName: string, key: string, value: string) => {
    const currentEnvVars = config.spec.environments[envName]?.environment || {};
    updateEnvironment(envName, 'environment', {
      ...currentEnvVars,
      [key]: value,
    });
  };

  const removeEnvironmentVariable = (envName: string, key: string) => {
    const currentEnvVars = { ...config.spec.environments[envName]?.environment };
    delete currentEnvVars[key];
    updateEnvironment(envName, 'environment', currentEnvVars);
  };

  return (
    <Box>
      {/* Validation Status */}
      <Box mb={2}>
        {validation.valid ? (
          <Chip 
            icon={<ValidateIcon />} 
            label="Configuration Valid" 
            color="primary" 
            size="small" 
          />
        ) : (
          <Chip 
            label={`${validation.errors.length} Errors`} 
            color="secondary" 
            size="small" 
          />
        )}
        <Button
          startIcon={<PreviewIcon />}
          onClick={generatePreview}
          size="small"
          style={{ marginLeft: 8 }}
        >
          Preview YAML
        </Button>
      </Box>

      <Tabs value={tabValue} onChange={(_, newValue) => setTabValue(newValue)}>
        <Tab label="Basic Info" />
        <Tab label="Environments" />
        <Tab label="Infrastructure" />
        <Tab label="Advanced" />
      </Tabs>

      <TabPanel value={tabValue} index={0}>
        <Grid container spacing={3}>
          <Grid item xs={12} md={6}>
            <TextField
              fullWidth
              label="Configuration Name"
              value={config.metadata.name}
              onChange={(e) => updateMetadata('name', e.target.value)}
              helperText="Unique name for this configuration"
              required
            />
          </Grid>
          <Grid item xs={12} md={6}>
            <TextField
              fullWidth
              label="Namespace"
              value={config.metadata.namespace}
              onChange={(e) => updateMetadata('namespace', e.target.value)}
              helperText="Kubernetes namespace"
              required
            />
          </Grid>
          <Grid item xs={12}>
            <TextField
              fullWidth
              label="Application Name"
              value={config.spec.application}
              onChange={(e) => setConfig(prev => ({
                ...prev,
                spec: { ...prev.spec, application: e.target.value }
              }))}
              helperText="Name of the application this configuration manages"
              required
            />
          </Grid>
        </Grid>
      </TabPanel>

      <TabPanel value={tabValue} index={1}>
        <Box mb={2}>
          <Typography variant="h6" gutterBottom>
            Environment Configurations
          </Typography>
          <FormControl>
            <InputLabel>Add Environment</InputLabel>
            <Select
              value=""
              onChange={(e) => addEnvironment(e.target.value as string)}
            >
              {environments
                .filter(env => !config.spec.environments[env])
                .map(env => (
                  <MenuItem key={env} value={env}>{env}</MenuItem>
                ))}
            </Select>
          </FormControl>
        </Box>

        {Object.entries(config.spec.environments).map(([envName, envConfig]) => (
          <Accordion key={envName} defaultExpanded>
            <AccordionSummary expandIcon={<ExpandMoreIcon />}>
              <Box display="flex" alignItems="center" width="100%">
                <Typography variant="subtitle1">{envName}</Typography>
                <Box flexGrow={1} />
                <IconButton
                  size="small"
                  onClick={(e) => {
                    e.stopPropagation();
                    removeEnvironment(envName);
                  }}
                >
                  <DeleteIcon />
                </IconButton>
              </Box>
            </AccordionSummary>
            <AccordionDetails>
              <Grid container spacing={2}>
                <Grid item xs={12} md={3}>
                  <TextField
                    fullWidth
                    type="number"
                    label="Replicas"
                    value={envConfig.replicas}
                    onChange={(e) => updateEnvironment(envName, 'replicas', parseInt(e.target.value))}
                  />
                </Grid>
                <Grid item xs={12} md={3}>
                  <FormControl fullWidth>
                    <InputLabel>Resource Size</InputLabel>
                    <Select
                      value="custom"
                      onChange={(e) => updateResourceSize(envName, e.target.value as any)}
                    >
                      <MenuItem value="small">Small (100m CPU, 128Mi RAM)</MenuItem>
                      <MenuItem value="medium">Medium (500m CPU, 512Mi RAM)</MenuItem>
                      <MenuItem value="large">Large (1 CPU, 1Gi RAM)</MenuItem>
                      <MenuItem value="custom">Custom</MenuItem>
                    </Select>
                  </FormControl>
                </Grid>
                <Grid item xs={12} md={3}>
                  <TextField
                    fullWidth
                    label="CPU Request"
                    value={envConfig.resources.requests.cpu}
                    onChange={(e) => updateEnvironment(envName, 'resources', {
                      ...envConfig.resources,
                      requests: { ...envConfig.resources.requests, cpu: e.target.value }
                    })}
                  />
                </Grid>
                <Grid item xs={12} md={3}>
                  <TextField
                    fullWidth
                    label="Memory Request"
                    value={envConfig.resources.requests.memory}
                    onChange={(e) => updateEnvironment(envName, 'resources', {
                      ...envConfig.resources,
                      requests: { ...envConfig.resources.requests, memory: e.target.value }
                    })}
                  />
                </Grid>

                {/* Environment Variables */}
                <Grid item xs={12}>
                  <Typography variant="subtitle2" gutterBottom>
                    Environment Variables
                  </Typography>
                  {Object.entries(envConfig.environment || {}).map(([key, value]) => (
                    <Box key={key} display="flex" alignItems="center" mb={1}>
                      <TextField
                        label="Key"
                        value={key}
                        size="small"
                        style={{ marginRight: 8 }}
                        disabled
                      />
                      <TextField
                        label="Value"
                        value={value}
                        size="small"
                        style={{ marginRight: 8 }}
                        onChange={(e) => addEnvironmentVariable(envName, key, e.target.value)}
                      />
                      <IconButton
                        size="small"
                        onClick={() => removeEnvironmentVariable(envName, key)}
                      >
                        <DeleteIcon />
                      </IconButton>
                    </Box>
                  ))}
                  <Button
                    startIcon={<AddIcon />}
                    size="small"
                    onClick={() => {
                      const key = prompt('Environment variable name:');
                      if (key) addEnvironmentVariable(envName, key, '');
                    }}
                  >
                    Add Variable
                  </Button>
                </Grid>
              </Grid>
            </AccordionDetails>
          </Accordion>
        ))}
      </TabPanel>

      <TabPanel value={tabValue} index={2}>
        <Typography variant="h6" gutterBottom>
          Infrastructure Components
        </Typography>
        <Typography variant="body2" color="textSecondary" paragraph>
          Configure databases, caches, and other infrastructure components.
        </Typography>
        <Typography variant="body2" color="textSecondary">
          Infrastructure configuration coming soon...
        </Typography>
      </TabPanel>

      <TabPanel value={tabValue} index={3}>
        <Typography variant="h6" gutterBottom>
          Advanced Settings
        </Typography>
        <Typography variant="body2" color="textSecondary">
          Advanced configuration options coming soon...
        </Typography>
      </TabPanel>

      {/* Error Display */}
      {!validation.valid && (
        <Box mt={2}>
          <Typography variant="subtitle2" color="error">
            Configuration Errors:
          </Typography>
          {validation.errors.map((error: string, index: number) => (
            <Typography key={index} variant="body2" color="error">
              • {error}
            </Typography>
          ))}
        </Box>
      )}

      {/* Action Buttons */}
      <Box mt={3} display="flex" justifyContent="flex-end" gap={1}>
        <Button onClick={onCancel}>
          Cancel
        </Button>
        <Button
          variant="contained"
          color="primary"
          onClick={() => onSave(config)}
          disabled={!validation.valid || !config.metadata.name || !config.spec.application}
        >
          Save Configuration
        </Button>
      </Box>

      {/* Preview Dialog */}
      {showPreview && (
        <Box mt={3}>
          <Typography variant="h6" gutterBottom>
            YAML Preview
          </Typography>
          <CodeSnippet
            text={preview}
            language="yaml"
            showCopyCodeButton
          />
          <Button onClick={() => setShowPreview(false)}>
            Close Preview
          </Button>
        </Box>
      )}
    </Box>
  );
};