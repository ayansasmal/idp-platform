// Authentication Setup Script for IDP Platform
// Handles AWS Cognito setup with LocalStack for development

import { execSync } from "node:child_process";

export async function main(config: {
  action?: string;
  create_test_users?: boolean;
  user_pool_name?: string;
  client_name?: string;
  dry_run?: boolean;
} = {}) {
  const { 
    action = "setup-full",
    create_test_users = true,
    user_pool_name = "idp-user-pool",
    client_name = "idp-client",
    dry_run = false 
  } = config;
  
  console.log(`🔐 Authentication setup - Action: ${action}${dry_run ? ' (dry run)' : ''}`);
  
  const results = {
    success: true,
    action,
    dry_run,
    cognito: {
      user_pool: null,
      client: null,
      domain: null,
      groups: [],
      users: []
    },
    environment_vars: {},
    errors: [],
    warnings: []
  };

  try {
    // Verify LocalStack is available
    if (!dryRun) {
      try {
        execSync('curl -s http://localhost:4566/_localstack/health', { timeout: 5000 });
      } catch (error) {
        throw new Error("LocalStack is not available. Please start infrastructure first.");
      }
    }

    switch (action) {
      case "setup-full":
        await setupCognitoUserPool(results, dry_run);
        await setupCognitoClient(results, dry_run);
        await setupCognitoDomain(results, dry_run);
        await setupCognitoGroups(results, dry_run);
        if (create_test_users) {
          await setupTestUsers(results, dry_run);
        }
        await generateEnvironmentVars(results);
        break;
      case "create-personas":
        await setupCognitoGroups(results, dry_run);
        await setupTestUsers(results, dry_run);
        break;
      case "status":
        await checkAuthStatus(results);
        break;
      case "test-auth":
        await testAuthentication(results);
        break;
      case "cleanup":
        await cleanupAuth(results, dry_run);
        break;
      default:
        throw new Error(`Unknown action: ${action}`);
    }

  } catch (error) {
    console.error(`💥 Authentication setup error: ${error.message}`);
    results.success = false;
    results.error = error.message;
  }

  return results;
}

async function setupCognitoUserPool(results: any, dryRun: boolean) {
  console.log("Creating Cognito User Pool...");

  if (dryRun) {
    console.log("DRY RUN: Would create Cognito User Pool");
    results.cognito.user_pool = { id: "us-east-1_DRY123", name: "idp-user-pool" };
    return;
  }

  try {
    // Check if user pool already exists
    const existingPools = execSync(
      'awslocal cognito-idp list-user-pools --max-results 50 --region us-east-1',
      { encoding: 'utf-8', timeout: 15000 }
    );
    
    const pools = JSON.parse(existingPools);
    let userPool = pools.UserPools?.find(p => p.Name === 'idp-user-pool');

    if (userPool) {
      console.log(`Found existing User Pool: ${userPool.Id}`);
      results.cognito.user_pool = {
        id: userPool.Id,
        name: userPool.Name,
        existing: true
      };
    } else {
      // Create new user pool
      const createPoolCmd = `awslocal cognito-idp create-user-pool \\
        --pool-name "idp-user-pool" \\
        --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}" \\
        --auto-verified-attributes email \\
        --username-attributes email \\
        --user-attribute-update-settings "AttributesRequireVerificationBeforeUpdate=[email]" \\
        --region us-east-1`;

      const poolResult = execSync(createPoolCmd, { encoding: 'utf-8', timeout: 15000 });
      const pool = JSON.parse(poolResult);
      
      console.log(`Created User Pool: ${pool.UserPool.Id}`);
      results.cognito.user_pool = {
        id: pool.UserPool.Id,
        name: pool.UserPool.Name,
        created: true
      };
    }

  } catch (error) {
    console.error(`Failed to setup User Pool: ${error.message}`);
    results.errors.push(`User Pool setup failed: ${error.message}`);
    throw error;
  }
}

async function setupCognitoClient(results: any, dryRun: boolean) {
  console.log("Creating Cognito User Pool Client...");

  if (dryRun) {
    console.log("DRY RUN: Would create Cognito Client");
    results.cognito.client = { id: "123456789abcdef", name: "idp-client" };
    return;
  }

  try {
    if (!results.cognito.user_pool?.id) {
      throw new Error("User Pool ID not available");
    }

    // Check if client already exists
    const existingClients = execSync(
      `awslocal cognito-idp list-user-pool-clients --user-pool-id "${results.cognito.user_pool.id}" --region us-east-1`,
      { encoding: 'utf-8', timeout: 15000 }
    );
    
    const clients = JSON.parse(existingClients);
    let client = clients.UserPoolClients?.find(c => c.ClientName === 'idp-client');

    if (client) {
      console.log(`Found existing Client: ${client.ClientId}`);
      results.cognito.client = {
        id: client.ClientId,
        name: client.ClientName,
        existing: true
      };
    } else {
      // Create new client
      const createClientCmd = `awslocal cognito-idp create-user-pool-client \\
        --user-pool-id "${results.cognito.user_pool.id}" \\
        --client-name "idp-client" \\
        --generate-secret \\
        --explicit-auth-flows "ADMIN_NO_SRP_AUTH" "USER_PASSWORD_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" \\
        --supported-identity-providers "COGNITO" \\
        --callback-urls "http://localhost:3000/api/auth/callback/cognito" "http://localhost:7007/api/auth/cognito/handler/frame" \\
        --logout-urls "http://localhost:3000" "http://localhost:7007" \\
        --allowed-o-auth-flows "code" \\
        --allowed-o-auth-scopes "openid" "profile" "email" \\
        --allowed-o-auth-flows-user-pool-client \\
        --region us-east-1`;

      const clientResult = execSync(createClientCmd, { encoding: 'utf-8', timeout: 15000 });
      const clientData = JSON.parse(clientResult);
      
      console.log(`Created Client: ${clientData.UserPoolClient.ClientId}`);
      results.cognito.client = {
        id: clientData.UserPoolClient.ClientId,
        name: clientData.UserPoolClient.ClientName,
        secret: clientData.UserPoolClient.ClientSecret,
        created: true
      };
    }

  } catch (error) {
    console.error(`Failed to setup Client: ${error.message}`);
    results.errors.push(`Client setup failed: ${error.message}`);
    throw error;
  }
}

async function setupCognitoDomain(results: any, dryRun: boolean) {
  console.log("Creating Cognito Domain...");

  if (dryRun) {
    console.log("DRY RUN: Would create Cognito Domain");
    results.cognito.domain = { name: "idp-platform", url: "https://idp-platform.auth.localhost.localstack.cloud:4566" };
    return;
  }

  try {
    if (!results.cognito.user_pool?.id) {
      throw new Error("User Pool ID not available");
    }

    const domainName = "idp-platform";
    
    // Check if domain already exists
    try {
      const existingDomain = execSync(
        `awslocal cognito-idp describe-user-pool-domain --domain "${domainName}" --region us-east-1`,
        { encoding: 'utf-8', timeout: 10000 }
      );
      
      const domain = JSON.parse(existingDomain);
      console.log(`Found existing domain: ${domainName}`);
      results.cognito.domain = {
        name: domainName,
        url: `https://${domainName}.auth.localhost.localstack.cloud:4566`,
        existing: true
      };
    } catch (error) {
      // Domain doesn't exist, create it
      const createDomainCmd = `awslocal cognito-idp create-user-pool-domain \\
        --user-pool-id "${results.cognito.user_pool.id}" \\
        --domain "${domainName}" \\
        --region us-east-1`;

      execSync(createDomainCmd, { timeout: 15000 });
      
      console.log(`Created domain: ${domainName}`);
      results.cognito.domain = {
        name: domainName,
        url: `https://${domainName}.auth.localhost.localstack.cloud:4566`,
        created: true
      };
    }

  } catch (error) {
    console.error(`Failed to setup domain: ${error.message}`);
    results.errors.push(`Domain setup failed: ${error.message}`);
    // Don't throw here, domain is not critical
  }
}

async function setupCognitoGroups(results: any, dryRun: boolean) {
  console.log("Creating Cognito Groups for RBAC...");

  const groups = [
    { name: "admin", description: "Platform Administrators - Full access to all resources and settings" },
    { name: "developer", description: "Application Developers - Can create, deploy and manage applications" },
    { name: "devops", description: "DevOps Engineers - Infrastructure management and deployment pipelines" },
    { name: "sre", description: "Site Reliability Engineers - Monitoring, observability and incident response" },
    { name: "support", description: "Support Engineers - Application monitoring and basic troubleshooting" },
    { name: "security", description: "Security Team - Security policies, compliance and audit access" },
    { name: "product", description: "Product Managers - Application insights and business metrics" },
    { name: "qa", description: "Quality Assurance - Testing environments and quality gates" },
    { name: "readonly", description: "Read-only Users - View access to applications and basic metrics" }
  ];

  if (dryRun) {
    console.log("DRY RUN: Would create RBAC groups");
    results.cognito.groups = groups.map(g => ({ ...g, created: true }));
    return;
  }

  try {
    if (!results.cognito.user_pool?.id) {
      throw new Error("User Pool ID not available");
    }

    for (const group of groups) {
      try {
        // Check if group exists
        const existingGroups = execSync(
          `awslocal cognito-idp list-groups --user-pool-id "${results.cognito.user_pool.id}" --region us-east-1`,
          { encoding: 'utf-8', timeout: 10000 }
        );
        
        const groupList = JSON.parse(existingGroups);
        const existingGroup = groupList.Groups?.find(g => g.GroupName === group.name);

        if (existingGroup) {
          console.log(`Group '${group.name}' already exists`);
          results.cognito.groups.push({ ...group, existing: true });
        } else {
          // Create group
          const createGroupCmd = `awslocal cognito-idp create-group \\
            --user-pool-id "${results.cognito.user_pool.id}" \\
            --group-name "${group.name}" \\
            --description "${group.description}" \\
            --region us-east-1`;

          execSync(createGroupCmd, { timeout: 10000 });
          console.log(`Created group: ${group.name}`);
          results.cognito.groups.push({ ...group, created: true });
        }
      } catch (error) {
        console.error(`Failed to create group ${group.name}: ${error.message}`);
        results.warnings.push(`Could not create group: ${group.name}`);
      }
    }

  } catch (error) {
    console.error(`Failed to setup groups: ${error.message}`);
    results.errors.push(`Groups setup failed: ${error.message}`);
  }
}

async function setupTestUsers(results: any, dryRun: boolean) {
  console.log("Creating test users...");

  const users = [
    { username: "admin", email: "admin@idp.local", groups: ["admin"], temporary_password: "TempPassword123!" },
    { username: "developer", email: "developer@idp.local", groups: ["developer"], temporary_password: "TempPassword123!" },
    { username: "devops", email: "devops@idp.local", groups: ["devops"], temporary_password: "TempPassword123!" },
    { username: "sre", email: "sre@idp.local", groups: ["sre"], temporary_password: "TempPassword123!" },
    { username: "support", email: "support@idp.local", groups: ["support"], temporary_password: "TempPassword123!" },
    { username: "security", email: "security@idp.local", groups: ["security"], temporary_password: "TempPassword123!" },
    { username: "product", email: "product@idp.local", groups: ["product"], temporary_password: "TempPassword123!" },
    { username: "readonly", email: "readonly@idp.local", groups: ["readonly"], temporary_password: "TempPassword123!" }
  ];

  if (dryRun) {
    console.log("DRY RUN: Would create test users");
    results.cognito.users = users.map(u => ({ ...u, created: true }));
    return;
  }

  try {
    if (!results.cognito.user_pool?.id) {
      throw new Error("User Pool ID not available");
    }

    for (const user of users) {
      try {
        // Check if user exists
        try {
          execSync(
            `awslocal cognito-idp admin-get-user --user-pool-id "${results.cognito.user_pool.id}" --username "${user.username}" --region us-east-1`,
            { encoding: 'utf-8', timeout: 10000 }
          );
          console.log(`User '${user.username}' already exists`);
          results.cognito.users.push({ ...user, existing: true });
          continue;
        } catch (error) {
          // User doesn't exist, create it
        }

        // Create user
        const createUserCmd = `awslocal cognito-idp admin-create-user \\
          --user-pool-id "${results.cognito.user_pool.id}" \\
          --username "${user.username}" \\
          --user-attributes Name=email,Value="${user.email}" Name=email_verified,Value=true \\
          --temporary-password "${user.temporary_password}" \\
          --message-action SUPPRESS \\
          --region us-east-1`;

        execSync(createUserCmd, { timeout: 15000 });

        // Set permanent password
        const setPasswordCmd = `awslocal cognito-idp admin-set-user-password \\
          --user-pool-id "${results.cognito.user_pool.id}" \\
          --username "${user.username}" \\
          --password "${user.temporary_password}" \\
          --permanent \\
          --region us-east-1`;

        execSync(setPasswordCmd, { timeout: 10000 });

        // Add user to groups
        for (const groupName of user.groups) {
          try {
            const addToGroupCmd = `awslocal cognito-idp admin-add-user-to-group \\
              --user-pool-id "${results.cognito.user_pool.id}" \\
              --username "${user.username}" \\
              --group-name "${groupName}" \\
              --region us-east-1`;

            execSync(addToGroupCmd, { timeout: 10000 });
          } catch (error) {
            console.warn(`Could not add ${user.username} to group ${groupName}: ${error.message}`);
          }
        }

        console.log(`Created user: ${user.username} (${user.email})`);
        results.cognito.users.push({ ...user, created: true });

      } catch (error) {
        console.error(`Failed to create user ${user.username}: ${error.message}`);
        results.warnings.push(`Could not create user: ${user.username}`);
      }
    }

  } catch (error) {
    console.error(`Failed to setup users: ${error.message}`);
    results.errors.push(`Users setup failed: ${error.message}`);
  }
}

async function generateEnvironmentVars(results: any) {
  console.log("Generating environment variables...");

  if (results.cognito.user_pool?.id && results.cognito.client?.id) {
    results.environment_vars = {
      AUTH_COGNITO_USER_POOL_ID: results.cognito.user_pool.id,
      AUTH_COGNITO_CLIENT_ID: results.cognito.client.id,
      AUTH_COGNITO_CLIENT_SECRET: results.cognito.client.secret || "not-available",
      AUTH_COGNITO_REGION: "us-east-1",
      AUTH_COGNITO_ISSUER: `http://localhost:4566/${results.cognito.user_pool.id}`,
      AUTH_COGNITO_ENDPOINT: "http://localhost:4566",
      AUTH_COGNITO_DOMAIN_URL: results.cognito.domain?.url || "not-configured"
    };

    console.log("Environment variables generated for Backstage configuration");
  } else {
    results.warnings.push("Could not generate environment variables - missing Cognito resources");
  }
}

async function checkAuthStatus(results: any) {
  console.log("Checking authentication status...");
  
  try {
    // Check user pools
    const pools = execSync('awslocal cognito-idp list-user-pools --max-results 10 --region us-east-1', 
      { encoding: 'utf-8', timeout: 10000 });
    const poolData = JSON.parse(pools);
    results.user_pools = poolData.UserPools?.length || 0;

    // Get detailed info for IDP pool
    const idpPool = poolData.UserPools?.find(p => p.Name === 'idp-user-pool');
    if (idpPool) {
      results.cognito.user_pool = { id: idpPool.Id, name: idpPool.Name };
      
      // Get clients
      const clients = execSync(
        `awslocal cognito-idp list-user-pool-clients --user-pool-id "${idpPool.Id}" --region us-east-1`,
        { encoding: 'utf-8', timeout: 10000 }
      );
      const clientData = JSON.parse(clients);
      results.clients = clientData.UserPoolClients?.length || 0;

      // Get groups
      const groups = execSync(
        `awslocal cognito-idp list-groups --user-pool-id "${idpPool.Id}" --region us-east-1`,
        { encoding: 'utf-8', timeout: 10000 }
      );
      const groupData = JSON.parse(groups);
      results.groups = groupData.Groups?.length || 0;
    }

  } catch (error) {
    results.errors.push(`Status check failed: ${error.message}`);
    results.success = false;
  }
}

async function testAuthentication(results: any) {
  console.log("Testing authentication...");
  
  // This would test actual authentication flow
  // For now, just verify services are accessible
  try {
    execSync('curl -s http://localhost:4566/_localstack/health', { timeout: 5000 });
    results.auth_service_available = true;
  } catch (error) {
    results.auth_service_available = false;
    results.errors.push("Authentication service not available");
  }
}

async function cleanupAuth(results: any, dryRun: boolean) {
  console.log("Cleaning up authentication resources...");
  
  if (dryRun) {
    console.log("DRY RUN: Would delete Cognito resources");
    return;
  }

  try {
    // List and delete user pools
    const pools = execSync('awslocal cognito-idp list-user-pools --max-results 50 --region us-east-1', 
      { encoding: 'utf-8', timeout: 10000 });
    const poolData = JSON.parse(pools);

    for (const pool of poolData.UserPools || []) {
      if (pool.Name === 'idp-user-pool') {
        try {
          // Delete domain first
          try {
            execSync(`awslocal cognito-idp delete-user-pool-domain --domain "idp-platform" --region us-east-1`, 
              { timeout: 10000 });
          } catch (error) {
            // Domain might not exist
          }

          // Delete user pool
          execSync(`awslocal cognito-idp delete-user-pool --user-pool-id "${pool.Id}" --region us-east-1`, 
            { timeout: 15000 });
          console.log(`Deleted user pool: ${pool.Id}`);
        } catch (error) {
          results.warnings.push(`Could not delete user pool ${pool.Id}: ${error.message}`);
        }
      }
    }

  } catch (error) {
    results.errors.push(`Cleanup failed: ${error.message}`);
  }
}