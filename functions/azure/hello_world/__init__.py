import azure.functions as func
import logging
import os
import uuid
import secrets
import string
from azure.identity import ClientSecretCredential

from msgraph import GraphServiceClient
from msgraph.generated.models.user import User
from msgraph.generated.models.password_profile import PasswordProfile
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.mgmt.authorization.models import RoleAssignmentCreateParameters, RoleAssignmentProperties


# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ClassroomManager:
    def __init__(self):
        logger.info("Initializing ClassroomManager")
        try:
            tenant_id = os.environ.get("AZURE_TENANT_ID")
            client_id = os.environ.get("AZURE_CLIENT_ID")
            client_secret = os.environ.get("AZURE_CLIENT_SECRET")
            subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
            
            if not all([tenant_id, client_id, client_secret, subscription_id]):
                raise ValueError("Missing required environment variables")
            self.subscription_id = subscription_id
            self.credential = ClientSecretCredential(
                tenant_id=tenant_id,
                client_id=client_id,
                client_secret=client_secret,
                subscription_id=subscription_id
            )
            
            self.graph_client = GraphServiceClient(
                credentials=self.credential,
                scopes=["https://graph.microsoft.com/.default"]
            )

             # Initialize the authorization client
            self.auth_client = AuthorizationManagementClient(
                credential=self.credential,
                subscription_id=self.subscription_id
            )
            
            logger.info("Successfully initialized Azure clients")
        except Exception as e:
            logger.error(f"Error initializing ClassroomManager: {str(e)}")
            raise

    def generate_password(self):
        """Generate a secure password"""
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
        password = ''.join(secrets.choice(alphabet) for i in range(16))
        return password
    
    def get_role_definition_id(self, role_name):
            # Fetch role definition ID using role name from custom roles
            definitions = self.auth_client.role_definitions.list(scope=f"/subscriptions/{self.subscription_id}")
            for definition in definitions:
                if definition.role_name == role_name:
                    return definition.id
            raise Exception(f"Role definition {role_name} not found")
    
    async def create_student_user(self):
        """Create a student user account"""
        try:
            username = f"student_{uuid.uuid4().hex[:8]}"
            password = self.generate_password()
            domain = os.environ.get("AZURE_DOMAIN", "paulabassaganasgmail.onmicrosoft.com")
            logger.info(f"Creating student user with username: {username}, password: {password}, domain: {domain}")

            request_body = User(
                account_enabled=True,
                display_name=f"Student {username}",
                mail_nickname=username,
                user_principal_name=f"{username}@{domain}",
                password_profile=PasswordProfile(
                    force_change_password_next_sign_in=False,
                    password=password
                )
            )

            logger.info(f"Request body: {request_body}")
            logger.info(f"Graph client: {self.graph_client}")
            created_user = await self.graph_client.users.post(request_body)
            logger.info(f"Created user: {created_user}")
            await self.assign_student_roles(created_user.id)
            logger.info(f"Assigned roles to user: {created_user.id}")
            return {
                "username": created_user.user_principal_name,
                "password": password
            }
        except Exception as e:
            logger.error(f"Error creating student user: {str(e)}")
            raise
    async def assign_student_roles(self, user_object_id):
        roles_to_assign = [
            "FunctionAppUser",
            "StorageUser",
            "EventHubUser",
            "CosmosDBUser",
            "CICDUser",
            "ResourceGroupUser",
            "ServicePrincipalRole",
            "StudentConsoleUser",
            "StudentServicePrincipalRole"
        ]
        
        assignments = []
        for role_name in roles_to_assign:
            role_def_id = self.get_role_definition_id(role_name)
            role_assignment_params = RoleAssignmentCreateParameters(
                role_definition_id=role_def_id,
                principal_id=user_object_id,
                principal_type='User'  # Make sure to set the principal type if needed
            )
            assignment = self.auth_client.role_assignments.create(
                scope=f"/subscriptions/{self.subscription_id}",
                role_assignment_name=str(uuid.uuid4()),  # UUID for the role assignment
                parameters=role_assignment_params
            )
            assignments.append(assignment)
            logger.info(f"Assigned role {role_name} to user {user_object_id}")

        return assignments
async def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')

    try:
        manager = ClassroomManager()
        credentials = await manager.create_student_user()
        
        return func.HttpResponse(
            f"""
            <html>
            <body>
                <h1>Your Azure Account</h1>
                <p><strong>Username:</strong> {credentials['username']}</p>
                <p><strong>Password:</strong> {credentials['password']}</p>
                <p><a href="https://portal.azure.com" target="_blank">Access Azure Portal</a></p>
            </body>
            </html>
            """,
            status_code=200,
            mimetype="text/html"
        )

    except Exception as e:
        logging.error(f"Error: {str(e)}")
        return func.HttpResponse(
            f"An error occurred: {str(e)}",
            status_code=500
        )