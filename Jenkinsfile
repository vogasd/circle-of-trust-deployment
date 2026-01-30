pipeline {
    agent any
    
    environment {
        // Azure Configuration
        AZURE_SUBSCRIPTION_ID = credentials('azure-subscription-id')
        ACR_NAME = 'circlerecristry'
        ACR_LOGIN_SERVER = "${ACR_NAME}.azurecr.io"
        AKS_CLUSTER_NAME = 'circle-aks-cluster'
        AKS_RESOURCE_GROUP = 'circle-rg'
        ARGOCD_SERVER = 'argocd.circle.internal'
        ARGOCD_APP = 'circle-of-trust-prod'
        LOG_ANALYTICS_RESOURCE_ID = ''
        
        // Application Configuration
        APP_NAME = 'circle-of-trust'
        BACKEND_IMAGE = "${ACR_LOGIN_SERVER}/circle-backend"
        FRONTEND_IMAGE = "${ACR_LOGIN_SERVER}/circle-frontend"
        OLLAMA_IMAGE = "${ACR_LOGIN_SERVER}/circle-ollama"
        
        // GitOps Repository
        GITOPS_REPO = 'https://github.com/your-org/circle-gitops.git'
        GITOPS_BRANCH = 'main'
        
        // Version Tags
        VERSION = "${env.BUILD_NUMBER}"
        
        // Security Scanning
        SONARQUBE_SERVER = 'SonarQube'
        TRIVY_CACHE_DIR = '/tmp/trivy-cache'
        
        // Deployment
        NAMESPACE = 'circle-prod'
        SLACK_CHANNEL = '#deployments'
        BACKEND_SERVICE_PORT = '8001'
    }
    
    options {
        timestamps()
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30', daysToKeepStr: '30'))
        disableConcurrentBuilds()
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
                    // Store commit info for later use
                    env.GIT_COMMIT_MSG = sh(script: "git log -1 --pretty=%B", returnStdout: true).trim()
                    env.GIT_AUTHOR = sh(script: "git log -1 --pretty=%an", returnStdout: true).trim()
                }
            }
        }
        
        stage('Validate Tooling') {
            steps {
                sh '''
                    set -e
                    required_tools="az kubectl docker docker-compose kustomize trivy sonar-scanner conftest polaris argocd python3 pytest npm"
                    for tool in $required_tools; do
                        command -v $tool >/dev/null 2>&1 || { echo "Missing required tool: $tool"; exit 1; }
                    done
                '''
            }
        }
        
        stage('Initialize') {
            steps {
                script {
                    echo "============================================"
                    echo "Circle of Trust - CI/CD Pipeline"
                    echo "Build: ${env.BUILD_NUMBER}"
                    echo "Commit: ${env.GIT_COMMIT_SHORT}"
                    echo "Image Tag: ${env.IMAGE_TAG}"
                    echo "============================================"
                    
                    // Send Slack notification
                    slackSend(
                        channel: SLACK_CHANNEL,
                        color: 'good',
                        message: "Starting deployment pipeline for ${APP_NAME}\nBuild: ${env.BUILD_NUMBER}\nCommit: ${env.GIT_COMMIT_SHORT}"
                    )
                }
            }
        }
        
        stage('Pre-Build Tests') {
            parallel {
                stage('Unit Tests - Backend') {
                    steps {
                        dir('backend') {
                            sh '''
                                python3 -m venv venv
                                . venv/bin/activate
                                pip install -q -r requirements.txt
                                pip install -q pytest pytest-cov pytest-mock
                                pytest tests/unit/ --cov=app --cov-report=xml --cov-report=html --junitxml=test-results.xml -v
                            '''
                        }
                    }
                    post {
                        always {
                            junit 'backend/test-results.xml'
                            publishHTML([
                                allowMissing: false,
                                alwaysLinkToLastBuild: true,
                                keepAll: true,
                                reportDir: 'backend/htmlcov',
                                reportFiles: 'index.html',
                                reportName: 'Backend Coverage Report'
                            ])
                        }
                    }
                }
                
                stage('Unit Tests - Frontend') {
                    steps {
                        dir('frontend') {
                            sh '''
                                npm ci
                                npm run test -- --coverage --watchAll=false
                            '''
                        }
                    }
                    post {
                        always {
                            publishHTML([
                                allowMissing: false,
                                alwaysLinkToLastBuild: true,
                                keepAll: true,
                                reportDir: 'frontend/coverage',
                                reportFiles: 'index.html',
                                reportName: 'Frontend Coverage Report'
                            ])
                        }
                    }
                }
                
                stage('Linting') {
                    steps {
                        parallel(
                            'Backend Linting': {
                                dir('backend') {
                                    sh '''
                                        python3 -m venv venv
                                        . venv/bin/activate
                                        pip install flake8 black pylint
                                        flake8 app/ --max-line-length=120 --output-file=flake8-report.txt || true
                                        black --check app/ || true
                                        pylint app/ --output-format=parseable --reports=no > pylint-report.txt || true
                                    '''
                                }
                            },
                            'Frontend Linting': {
                                dir('frontend') {
                                    sh '''
                                        npm run lint -- --output-file eslint-report.json --format json || true
                                    '''
                                }
                            }
                        )
                    }
                }
            }
        }
        
        stage('SAST Security Scanning') {
            parallel {
                stage('SonarQube Analysis') {
                    steps {
                        script {
                            withSonarQubeEnv(SONARQUBE_SERVER) {
                                sh '''
                                    sonar-scanner \
                                        -Dsonar.projectKey=circle-of-trust \
                                        -Dsonar.projectName="Circle of Trust" \
                                        -Dsonar.sources=. \
                                        -Dsonar.python.coverage.reportPaths=backend/coverage.xml \
                                        -Dsonar.javascript.lcov.reportPaths=frontend/coverage/lcov.info
                                '''
                            }
                        }
                    }
                }
                
                stage('Dependency Check') {
                    steps {
                        sh '''
                            # Python dependency check
                            cd backend
                            pip install safety
                            safety check --json --output safety-report.json
                            
                            # Node.js dependency check
                            cd ../frontend
                            npm audit --audit-level=critical --json > npm-audit-report.json
                        '''
                    }
                }
                
                stage('Secret Scanning') {
                    steps {
                        sh '''
                            # Install and run Gitleaks for secret detection
                            docker run --rm -v $(pwd):/code zricethezav/gitleaks:latest \
                                detect --source /code \
                                --report-path /code/gitleaks-report.json \
                                --no-git
                        '''
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            steps {
                script {
                    timeout(time: 5, unit: 'MINUTES') {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "Pipeline aborted due to quality gate failure: ${qg.status}"
                        }
                    }
                }
            }
        }
        
        stage('Build Container Images') {
            parallel {
                stage('Build Backend Image') {
                    steps {
                        script {
                            dir('backend') {
                                sh """
                                    docker build \
                                        --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                                        --build-arg VERSION=${IMAGE_TAG} \
                                        --build-arg VCS_REF=${GIT_COMMIT_SHORT} \
                                        -t ${BACKEND_IMAGE}:${IMAGE_TAG} \
                                        -t ${BACKEND_IMAGE}:latest \
                                        -f Dockerfile .
                                """
                            }
                        }
                    }
                }
                
                stage('Build Frontend Image') {
                    steps {
                        script {
                            dir('frontend') {
                                sh """
                                    docker build \
                                        --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                                        --build-arg VERSION=${IMAGE_TAG} \
                                        -t ${FRONTEND_IMAGE}:${IMAGE_TAG} \
                                        -t ${FRONTEND_IMAGE}:latest \
                                        -f Dockerfile .
                                """
                            }
                        }
                    }
                }
                
                stage('Build Ollama Image') {
                    steps {
                        script {
                            dir('ollama') {
                                sh """
                                    docker build \
                                        --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                                        --build-arg VERSION=${IMAGE_TAG} \
                                        -t ${OLLAMA_IMAGE}:${IMAGE_TAG} \
                                        -t ${OLLAMA_IMAGE}:latest \
                                        -f Dockerfile .
                                """
                            }
                        }
                    }
                }
            }
        }
        
        stage('Container Security Scanning') {
            parallel {
                stage('Scan Backend Image') {
                    steps {
                        sh """
                            trivy image \
                                --severity CRITICAL \
                                --exit-code 1 \
                                --format json \
                                --output trivy-backend-report.json \
                                ${BACKEND_IMAGE}:${IMAGE_TAG}
                        """
                    }
                }
                
                stage('Scan Frontend Image') {
                    steps {
                        sh """
                            trivy image \
                                --severity CRITICAL \
                                --exit-code 1 \
                                --format json \
                                --output trivy-frontend-report.json \
                                ${FRONTEND_IMAGE}:${IMAGE_TAG}
                        """
                    }
                }
                
                stage('Scan Ollama Image') {
                    steps {
                        sh """
                            trivy image \
                                --severity CRITICAL \
                                --exit-code 1 \
                                --format json \
                                --output trivy-ollama-report.json \
                                ${OLLAMA_IMAGE}:${IMAGE_TAG}
                        """
                    }
                }
            }
            post {
                always {
                    script {
                        // Parse Trivy results and fail if critical vulnerabilities found
                        def backendVulns = readJSON file: 'trivy-backend-report.json'
                        def frontendVulns = readJSON file: 'trivy-frontend-report.json'
                        def ollamaVulns = readJSON file: 'trivy-ollama-report.json'
                        
                        // Archive reports
                        archiveArtifacts artifacts: 'trivy-*-report.json', allowEmptyArchive: true
                    }
                }
            }
        }
        
        stage('Integration Tests') {
            steps {
                script {
                    sh '''
                        # Start containers for integration testing
                        docker-compose -f docker-compose.test.yml up -d
                        
                        # Wait for services to be ready
                        sleep 30
                        
                        # Run integration tests inside the backend container
                        docker-compose -f docker-compose.test.yml exec -T backend \
                            pytest tests/integration/ --junitxml=/tmp/integration-test-results.xml -v || true
                        
                        # Copy results out of container
                        docker-compose -f docker-compose.test.yml cp backend:/tmp/integration-test-results.xml ./integration-test-results.xml || true
                    '''
                }
            }
            post {
                always {
                    sh 'docker-compose -f docker-compose.test.yml down -v || true'
                    junit 'integration-test-results.xml'
                }
            }
        }
        
        stage('Push to Registry') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'azure-acr-credentials',
                        usernameVariable: 'ACR_USER',
                        passwordVariable: 'ACR_PASSWORD'
                    )]) {
                        sh """
                            echo \${ACR_PASSWORD} | docker login ${ACR_LOGIN_SERVER} -u \${ACR_USER} --password-stdin
                            
                            # Push backend image
                            docker push ${BACKEND_IMAGE}:${IMAGE_TAG}
                            docker push ${BACKEND_IMAGE}:latest
                            
                            # Push frontend image
                            docker push ${FRONTEND_IMAGE}:${IMAGE_TAG}
                            docker push ${FRONTEND_IMAGE}:latest
                            
                            # Push ollama image
                            docker push ${OLLAMA_IMAGE}:${IMAGE_TAG}
                            docker push ${OLLAMA_IMAGE}:latest
                            
                            docker logout ${ACR_LOGIN_SERVER}
                        """
                    }
                }
            }
        }
        
        stage('Update GitOps Repository') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'github-credentials',
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_TOKEN'
                    )]) {
                        sh """
                            # Clone GitOps repository
                            rm -rf gitops-repo
                            repo_no_proto=\$(echo "${GITOPS_REPO}" | sed 's#https\?://##')
                            git clone https://\${GIT_USER}:\${GIT_TOKEN}@\${repo_no_proto} gitops-repo
                            cd gitops-repo
                            
                            # Update image tags in Kustomize overlays
                            cd overlays/production
                            
                            # Update backend image
                            kustomize edit set image ${BACKEND_IMAGE}=${BACKEND_IMAGE}:${IMAGE_TAG}
                            
                            # Update frontend image
                            kustomize edit set image ${FRONTEND_IMAGE}=${FRONTEND_IMAGE}:${IMAGE_TAG}
                            
                            # Update ollama image
                            kustomize edit set image ${OLLAMA_IMAGE}=${OLLAMA_IMAGE}:${IMAGE_TAG}
                            
                            # Commit and push changes
                            git config user.email "jenkins@circleci.com"
                            git config user.name "Jenkins CI"
                            git add .
                            git commit -m "Update images to version ${IMAGE_TAG}" || true
                            git push origin ${GITOPS_BRANCH}
                        """
                    }
                }
            }
        }
        
        stage('Deploy to AKS (GitOps)') {
            steps {
                script {
                    withCredentials([string(credentialsId: 'argocd-auth-token', variable: 'ARGOCD_AUTH_TOKEN')]) {
                        sh """
                            # Trigger ArgoCD sync for GitOps deployment
                            argocd login ${ARGOCD_SERVER} --auth-token \$ARGOCD_AUTH_TOKEN --grpc-web
                            argocd app sync ${ARGOCD_APP} --prune --timeout 600
                            argocd app wait ${ARGOCD_APP} --health --timeout 600
                        """
                    }
                }
            }
        }
        
        stage('Configure Cluster Access') {
            steps {
                script {
                    withCredentials([azureServicePrincipal('azure-service-principal')]) {
                        sh """
                            # Login to Azure
                            az login --service-principal \
                                -u \$AZURE_CLIENT_ID \
                                -p \$AZURE_CLIENT_SECRET \
                                --tenant \$AZURE_TENANT_ID
                            
                            # Get AKS credentials
                            az aks get-credentials \
                                --resource-group ${AKS_RESOURCE_GROUP} \
                                --name ${AKS_CLUSTER_NAME} \
                                --overwrite-existing
                        """
                    }
                }
            }
        }
        
        stage('Post-Deployment Tests') {
            parallel {
                stage('Health Check') {
                    steps {
                        script {
                            sh """
                                # Run in-cluster health checks against ClusterIP service
                                kubectl -n ${NAMESPACE} run circle-healthcheck \
                                    --rm -i --restart=Never \
                                    --image=curlimages/curl:8.5.0 \
                                    --command -- /bin/sh -c \
                                    "curl -fsS http://circle-backend.${NAMESPACE}.svc.cluster.local:${BACKEND_SERVICE_PORT}/health && \
                                     curl -fsS http://circle-backend.${NAMESPACE}.svc.cluster.local:${BACKEND_SERVICE_PORT}/ready"
                            """
                        }
                    }
                }
                
                stage('Smoke Tests') {
                    steps {
                        script {
                            sh '''
                                # Setup test environment
                                python3 -m venv test-venv
                                . test-venv/bin/activate
                                pip install -q -r tests/requirements.txt
                                
                                # Set BASE_URL for deployed application
                                export BASE_URL="http://circle-backend.${NAMESPACE}.svc.cluster.local:${BACKEND_SERVICE_PORT}"
                                
                                # Run smoke tests against deployed application
                                pytest tests/smoke/ -v \
                                    --junitxml=smoke-test-results.xml \
                                    --tb=short
                            '''
                        }
                    }
                    post {
                        always {
                            junit 'smoke-test-results.xml'
                        }
                    }
                }
                
                stage('Performance Tests') {
                    steps {
                        script {
                            sh """
                                # Run basic load test with k6
                                docker run --rm -v \$(pwd)/tests/performance:/scripts \
                                    loadimpact/k6:latest run /scripts/basic-load-test.js
                            """
                        }
                    }
                }
            }
        }
        
        stage('Policy Enforcement') {
            steps {
                script {
                    sh """
                        # Build manifests from Kustomize for policy checks
                        kustomize build gitops-repo/overlays/production > /tmp/circle-manifests.yaml

                        # Run OPA policy checks (fail on violations)
                        conftest test /tmp/circle-manifests.yaml \
                            --policy policies/ \
                            --output json > policy-report.json
                        
                        # Run Kubernetes policy audit with Polaris (fail on errors)
                        polaris audit \
                            --audit-path gitops-repo/overlays/production/ \
                            --format json \
                            --set-exit-code-on-error > polaris-report.json
                    """
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: '*-report.json', allowEmptyArchive: true
                }
            }
        }
        
        stage('Monitoring Setup') {
            steps {
                script {
                    sh """
                        # Create Prometheus ServiceMonitor for the application
                        kubectl apply -f monitoring/service-monitor.yaml -n ${NAMESPACE}
                        
                        # Create Grafana dashboard ConfigMap
                        kubectl apply -f monitoring/grafana-dashboard.yaml -n circle-monitoring
                    """
                }
            }
        }
        
        stage('Logging & Audit Setup') {
            steps {
                script {
                    sh """
                        # Deploy Fluent Bit for log aggregation
                        kubectl apply -f monitoring/fluent-bit.yaml
                        
                        if [ -n "${LOG_ANALYTICS_RESOURCE_ID}" ]; then
                            echo "Configuring AKS diagnostics to Log Analytics"
                            AKS_ID=\$(az aks show -g ${AKS_RESOURCE_GROUP} -n ${AKS_CLUSTER_NAME} --query id -o tsv)
                            az monitor diagnostic-settings create \
                                --name circle-aks-diagnostics \
                                --resource \${AKS_ID} \
                                --workspace ${LOG_ANALYTICS_RESOURCE_ID} \
                                --logs '[{"category":"kube-apiserver","enabled":true},{"category":"kube-audit","enabled":true},{"category":"kube-audit-admin","enabled":true},{"category":"kube-controller-manager","enabled":true},{"category":"kube-scheduler","enabled":true},{"category":"cluster-autoscaler","enabled":true},{"category":"guard","enabled":true}]' \
                                --metrics '[{"category":"AllMetrics","enabled":true}]' || true
                        else
                            echo "LOG_ANALYTICS_RESOURCE_ID not set; skipping Log Analytics diagnostics."
                        fi
                    """
                }
            }
        }
    }
    
    post {
        success {
            script {
                slackSend(
                    channel: SLACK_CHANNEL,
                    color: 'good',
                    message: """
                        ✅ Deployment Successful!
                        Application: ${APP_NAME}
                        Build: ${env.BUILD_NUMBER}
                        Version: ${IMAGE_TAG}
                        Commit: ${GIT_COMMIT_SHORT}
                        Author: ${env.GIT_AUTHOR}
                        Duration: ${currentBuild.durationString}
                    """
                )
                
                // Create deployment record in audit log
                sh """
                    kubectl annotate deployment/circle-backend \
                        deployment.kubernetes.io/revision-timestamp=\$(date -Iseconds) \
                        deployment.kubernetes.io/deployed-by='Jenkins' \
                        deployment.kubernetes.io/build-number='${env.BUILD_NUMBER}' \
                        deployment.kubernetes.io/git-commit='${GIT_COMMIT_SHORT}' \
                        -n ${NAMESPACE}
                """
            }
        }
        
        failure {
            script {
                slackSend(
                    channel: SLACK_CHANNEL,
                    color: 'danger',
                    message: """
                        ❌ Deployment Failed!
                        Application: ${APP_NAME}
                        Build: ${env.BUILD_NUMBER}
                        Commit: ${GIT_COMMIT_SHORT}
                        Stage: ${env.STAGE_NAME}
                        Check: ${env.BUILD_URL}
                    """
                )
                
                // Trigger rollback if deployment failed
                if (env.STAGE_NAME == 'Deploy to AKS (GitOps)' || env.STAGE_NAME == 'Post-Deployment Tests') {
                    echo "Triggering automatic rollback..."
                    build job: 'circle-rollback', parameters: [
                        string(name: 'NAMESPACE', value: NAMESPACE),
                        string(name: 'ROLLBACK_REVISION', value: '')
                    ], wait: false
                }
            }
        }
        
        always {
            script {
                // Archive all reports
                archiveArtifacts artifacts: '**/*-report.*', allowEmptyArchive: true
                
                // Clean up workspace
                cleanWs()
            }
        }
    }
}
