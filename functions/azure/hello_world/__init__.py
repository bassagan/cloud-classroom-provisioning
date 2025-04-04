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
from msgraph.generated.models.reference_create import ReferenceCreate


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
            
            # Add user to the students group

            
            return {
                "username": created_user.user_principal_name,
                "password": password
            }
        except Exception as e:
            logger.error(f"Error creating student user: {str(e)}")
            raise
    async def assign_student_roles(self, user_object_id):
        """
        Add the user to the students group
        """
        try:
            group_id = os.environ.get("STUDENTS_GROUP_ID")
            if not group_id:
                raise ValueError("STUDENTS_GROUP_ID environment variable not set")
            
            # Create a proper reference object instead of a dict
            reference = ReferenceCreate(
                odata_id=f"https://graph.microsoft.com/v1.0/users/{user_object_id}"
            )
            
            await self.graph_client.groups.by_group_id(group_id).members.ref.post(
                body=reference
            )
            logger.info(f"Added user {user_object_id} to students group")
        except Exception as e:
            logger.error(f"Error adding user to students group: {str(e)}")
            raise

async def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')

    try:
        manager = ClassroomManager()
        credentials = await manager.create_student_user()
        
        return func.HttpResponse(
            f"""
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Cloud Classroom Access</title>
                <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
                <style>
                    :root {{
                        --pink: #f452cb;
                        --background-purple: #3f0383;
                        --yellow: #ffd101;
                        --dark-blue: #1B1464;
                        --white: #FFFFFF;
                    }}
                    
                    html {{
                        font-size: 62.5%;
                        -webkit-font-smoothing: antialiased;
                        -moz-osx-font-smoothing: grayscale;
                    }}
                    
                    body {{
                        font-family: 'Open Sans', sans-serif;
                        font-size: 2.1rem;
                        font-weight: 300;
                        line-height: 1.2;
                        margin: 0;
                        padding-top: 80px;
                        overflow-x: hidden;
                        background-color: var(--background-purple);
                        color: var(--white);
                    }}

                    .top-bar {{
                        position: fixed;
                        top: 0;
                        left: 0;
                        right: 0;
                        z-index: 9999;
                        background: var(--pink);
                        color: white;
                        box-shadow: 0 2px 6px 0 rgba(0, 0, 0, .07);
                        transition: all .3s cubic-bezier(1, 0.18, 1, 1);
                        height: 80px;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    }}

                    .top-bar .wrap {{
                        padding: 8px 0;
                        font-size: 2.4rem;
                        font-weight: 700;
                        text-align: center;
                    }}

                    .container {{
                        max-width: 1200px;
                        margin: 0 auto;
                        padding: 2rem;
                    }}

                    .section-title {{
                        position: relative;
                        color: var(--white);
                        font-size: 4rem;
                        font-weight: 700;
                        margin-bottom: 3rem;
                        padding-bottom: 1.5rem;
                        text-align: center;
                    }}

                    .section-title:after {{
                        content: '';
                        position: absolute;
                        bottom: 0;
                        left: 50%;
                        transform: translateX(-50%);
                        width: 120px;
                        height: 4px;
                        background: var(--pink);
                    }}

                    .credentials-section {{
                        display: grid;
                        grid-template-columns: minmax(auto, max-content) minmax(300px, 1fr);
                        gap: 3rem;
                        margin: 4rem 0;
                        justify-content: center;
                    }}

                    .card {{
                        border-radius: 15px;
                        padding: 3rem;
                        position: relative;
                        overflow: hidden;
                        box-shadow: 0 8px 24px rgba(0,0,0,0.2);
                        width: 100%;
                    }}

                    .card::before {{
                        content: '';
                        position: absolute;
                        top: 0;
                        left: 0;
                        width: 100%;
                        height: 8px;
                        background: var(--pink);
                    }}

                    .individual-credentials {{
                        background: var(--yellow);
                        border: 3px solid var(--dark-blue);
                        min-width: min-content;
                    }}

                    .group-info {{
                        background: var(--pink);
                        color: var(--white);
                    }}

                    .card h2 {{
                        font-size: 3rem;
                        font-weight: 700;
                        margin-top: 0;
                        margin-bottom: 2rem;
                        color: var(--background-purple);
                    }}

                    .group-info h2 {{
                        color: var(--white);
                    }}

                    .credential-item {{
                        margin-bottom: 2rem;
                    }}

                    .credential-item strong {{
                        display: block;
                        margin-bottom: 1rem;
                        font-size: 2rem;
                        font-weight: 600;
                        color: var(--background-purple);
                    }}

                    .credential-value {{
                        background: var(--white);
                        padding: 1.5rem;
                        border-radius: 8px;
                        font-family: monospace;
                        font-size: 1.8rem;
                        box-shadow: 0 4px 6px rgba(0,0,0,0.1);
                        color: var(--background-purple);
                        white-space: nowrap;
                        display: flex;
                        justify-content: space-between;
                        align-items: center;
                        gap: 1rem;
                        position: relative;
                    }}

                    .credential-text {{
                        flex: 1;
                        overflow-x: auto;
                        padding-right: 1rem;
                    }}

                    /* Hide scrollbar for credential text while allowing scroll */
                    .credential-text::-webkit-scrollbar {{
                        display: none;
                    }}
                    
                    .credential-text {{
                        -ms-overflow-style: none;
                        scrollbar-width: none;
                    }}

                    .copy-button {{
                        background: var(--background-purple);
                        border: none;
                        border-radius: 4px;
                        padding: 0.8rem 1.2rem;
                        cursor: pointer;
                        color: var(--white);
                        transition: all 0.3s ease;
                        font-size: 1.4rem;
                        font-weight: 600;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        min-width: 70px;
                    }}

                    .copy-button:hover {{
                        background-color: var(--pink);
                        transform: translateY(-1px);
                    }}

                    .action-button {{
                        display: inline-block;
                        background-color: var(--yellow);
                        color: var(--background-purple);
                        padding: 1.5rem 3rem;
                        text-decoration: none;
                        border-radius: 50px;
                        transition: all 0.3s ease;
                        font-weight: 700;
                        font-size: 1.8rem;
                        text-transform: uppercase;
                        letter-spacing: 1px;
                        margin-top: 2rem;
                        border: none;
                        cursor: pointer;
                    }}

                    .action-button:hover {{
                        background-color: var(--white);
                        transform: translateY(-2px);
                        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
                    }}

                    .important-notice {{
                        background-color: var(--background-purple);
                        color: var(--white);
                        padding: 1.5rem;
                        border-radius: 8px;
                        margin-top: 2rem;
                        font-weight: 500;
                        font-size: 1.6rem;
                        border-left: 4px solid var(--pink);
                    }}

                    .footer {{
                        text-align: center;
                        margin-top: 4rem;
                        padding: 3rem;
                        background-color: var(--pink);
                        color: var(--white);
                        border-radius: 15px;
                        position: relative;
                    }}

                    .footer::before {{
                        content: '';
                        position: absolute;
                        top: 0;
                        left: 50%;
                        transform: translateX(-50%);
                        width: 100px;
                        height: 4px;
                        background: var(--yellow);
                    }}

                    @media (max-width: 1200px) {{
                        .credentials-section {{
                            grid-template-columns: minmax(auto, 1fr) minmax(auto, 1fr);
                        }}
                        
                        .container {{
                            padding: 1.5rem;
                        }}
                    }}

                    @media (max-width: 900px) {{
                        .credentials-section {{
                            grid-template-columns: 1fr;
                        }}

                        .individual-credentials {{
                            width: auto;
                            max-width: 100%;
                        }}

                        .credential-value {{
                            font-size: 1.6rem;
                        }}
                    }}

                    @media (max-width: 480px) {{
                        .top-bar .wrap {{
                            font-size: 1.8rem;
                            padding: 8px 15px;
                        }}

                        .section-title {{
                            font-size: 2.8rem;
                        }}

                        .card {{
                            padding: 2rem;
                        }}

                        .card h2 {{
                            font-size: 2.2rem;
                        }}

                        .credential-value {{
                            font-size: 1.4rem;
                        }}
                    }}

                    /* Add styles for horizontal scrolling indicator */
                    .scroll-indicator {{
                        position: absolute;
                        right: 10px;
                        bottom: 10px;
                        background: rgba(0,0,0,0.1);
                        padding: 4px 8px;
                        border-radius: 4px;
                        font-size: 1.2rem;
                        opacity: 0;
                        transition: opacity 0.3s;
                    }}

                    .credential-value:hover + .scroll-indicator {{
                        opacity: 1;
                    }}

                    .credential-container {{
                        display: flex;
                        align-items: center;
                        gap: 1rem;
                    }}

                    .download-button {{
                        display: block;
                        width: 100%;
                        background-color: var(--background-purple);
                        color: var(--white);
                        border: none;
                        border-radius: 8px;
                        padding: 1.5rem;
                        margin-top: 2rem;
                        font-size: 1.6rem;
                        cursor: pointer;
                        transition: all 0.3s ease;
                        font-weight: 600;
                    }}

                    .download-button:hover {{
                        background-color: var(--pink);
                        transform: translateY(-2px);
                    }}
                </style>
                <script>
                    function copyToClipboard(text, elementId) {{
                        navigator.clipboard.writeText(text).then(function() {{
                            const element = document.getElementById(elementId);
                            const originalText = element.innerHTML;
                            element.innerHTML = 'Copied!';
                            setTimeout(function() {{
                                element.innerHTML = 'Copy';
                            }}, 2000);
                        }});
                    }}

                    function downloadCSV() {{
                        const username = document.querySelector('.credential-value').textContent;
                        const password = document.querySelectorAll('.credential-value')[1].textContent;
                        const csvContent = `Username,Password\n${{username}},${{password}}`;
                        const blob = new Blob([csvContent], {{ type: 'text/csv' }});
                        const url = window.URL.createObjectURL(blob);
                        const a = document.createElement('a');
                        a.setAttribute('href', url);
                        a.setAttribute('download', 'cloud_classroom_credentials.csv');
                        document.body.appendChild(a);
                        a.click();
                        document.body.removeChild(a);
                        window.URL.revokeObjectURL(url);
                    }}
                </script>
            </head>
            <body>
                <div class="top-bar">
                    <div class="wrap">
                        Your Cloud Classroom is Ready!
                    </div>
                </div>
                
                <div class="container">
                    <h1 class="section-title">Welcome to Testus Patronus</h1>
                    
                    <div class="credentials-section">
                        <div class="card individual-credentials">
                            <h2>Your Credentials</h2>
                            <div class="credential-item">
                                <strong>Username</strong>
                                <div class="credential-value">
                                    <span class="credential-text">{credentials['username']}</span>
                                    <button class="copy-button" id="copyUsername" 
                                        onclick="copyToClipboard('{credentials['username']}', 'copyUsername')">
                                        Copy
                                    </button>
                                </div>
                            </div>
                            
                            <div class="credential-item">
                                <strong>Password</strong>
                                <div class="credential-value">
                                    <span class="credential-text">{credentials['password']}</span>
                                    <button class="copy-button" id="copyPassword" 
                                        onclick="copyToClipboard('{credentials['password']}', 'copyPassword')">
                                        Copy
                                    </button>
                                </div>
                            </div>
                            
                            <div class="important-notice">
                                <strong>Important:</strong> Save these credentials securely!
                            </div>
                            
                            <button onclick="downloadCSV()" class="download-button">
                                Download Credentials (CSV)
                            </button>
                        </div>
                        
                        <div class="card group-info">
                            <h2>Next Steps</h2>
                            <p>1. Save your credentials</p>
                            <p>2. Access the Azure Portal</p>
                            <p>3. Start exploring your cloud environment</p>
                            <a href="https://portal.azure.com" target="_blank" class="action-button">
                                Launch Azure Portal
                            </a>
                        </div>
                    </div>

                    <div class="footer">
                        <p>Cloud Classroom Provisioning System</p>
                        <small>Powered by Bassagan</small>
                    </div>
                </div>
            </body>
            </html>
            """,
            status_code=200,
            mimetype="text/html"
        )

    except Exception as e:
        logging.error(f"Error: {str(e)}")
        return func.HttpResponse(
            f"""
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Cloud Classroom - Error</title>
                <style>
                    :root {{
                        --pink: #f452cb;
                        --background-purple: #3f0383;
                        --yellow: #ffd101;
                        --dark-blue: #1B1464;
                        --white: #FFFFFF;
                    }}
                    
                    html {{
                        font-size: 62.5%;
                        -webkit-font-smoothing: antialiased;
                        -moz-osx-font-smoothing: grayscale;
                    }}
                    
                    body {{
                        font-family: 'Open Sans', sans-serif;
                        font-size: 2.1rem;
                        font-weight: 300;
                        line-height: 1.2;
                        margin: 0;
                        padding-top: 80px;
                        overflow-x: hidden;
                        background-color: var(--background-purple);
                        color: var(--white);
                    }}

                    .top-bar {{
                        position: fixed;
                        top: 0;
                        left: 0;
                        right: 0;
                        z-index: 9999;
                        background: var(--pink);
                        color: white;
                        box-shadow: 0 2px 6px 0 rgba(0, 0, 0, .07);
                        height: 80px;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    }}

                    .container {{
                        max-width: 800px;
                        margin: 0 auto;
                        padding: 2rem;
                        text-align: center;
                    }}

                    .error-card {{
                        background: var(--white);
                        border-radius: 15px;
                        padding: 3rem;
                        margin-top: 4rem;
                        box-shadow: 0 8px 24px rgba(0,0,0,0.2);
                        border: 3px solid var(--pink);
                    }}

                    .error-title {{
                        color: var(--pink);
                        font-size: 3rem;
                        font-weight: 700;
                        margin-bottom: 2rem;
                    }}

                    .error-message {{
                        color: var(--background-purple);
                        font-size: 2rem;
                        margin-bottom: 3rem;
                    }}

                    .action-button {{
                        display: inline-block;
                        background-color: var(--yellow);
                        color: var(--background-purple);
                        padding: 1.5rem 3rem;
                        text-decoration: none;
                        border-radius: 50px;
                        transition: all 0.3s ease;
                        font-weight: 700;
                        font-size: 1.8rem;
                        text-transform: uppercase;
                        letter-spacing: 1px;
                        border: none;
                        cursor: pointer;
                    }}

                    .action-button:hover {{
                        background-color: var(--pink);
                        color: var(--white);
                        transform: translateY(-2px);
                        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
                    }}
                </style>
            </head>
            <body>
                <div class="top-bar">
                    <div class="wrap">
                        Cloud Classroom
                    </div>
                </div>
                
                <div class="container">
                    <div class="error-card">
                        <h1 class="error-title">Oops! Something went wrong</h1>
                        <p class="error-message">
                            An error occurred while creating your user account.<br>
                            Please refresh the page or try again later.
                        </p>
                        <a href="javascript:window.location.reload()" class="action-button">
                            Try Again
                        </a>
                    </div>
                </div>
            </body>
            </html>
            """,
            status_code=500,
            mimetype="text/html"
        )