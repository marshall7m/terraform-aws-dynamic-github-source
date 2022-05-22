import boto3
import datetime
import logging
import time
import os
import github

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

class TimeoutError(Exception):
    pass

def lambda_invocation_count(function_name, start_time, end_time=None):
    '''
    Returns the number of times a Lambda Function has runned since the passed start_time
    
    Argruments:
        function_name: Name of the AWS Lambda function
        refresh: Determines if a refreshed invocation count should be returned. If False, returns the locally stored invocation count.
    '''
    invocations = []
    if not end_time:
        end_time = datetime.datetime.now(datetime.timezone.utc)

    log.debug(f'Start Time: {start_time} -- End Time: {end_time}')

    cw = boto3.client('cloudwatch')

    response = cw.get_metric_statistics(
        Namespace='AWS/Lambda',
        MetricName='Invocations',
        Dimensions=[
            {
                'Name': 'FunctionName',
                'Value': function_name
            }
        ],
        StartTime=start_time, 
        EndTime=end_time,
        Period=60,
        Statistics=[
            'SampleCount'
        ],
        Unit='Count'
    )
    for data in response['Datapoints']:
        invocations.append(data['SampleCount'])
        
    return len(invocations)

def wait_for_lambda_invocation(function_name, start_time, timeout=60):
    '''Waits for Lambda's completed invocation count to be more than the current invocation count stored'''
    start_count = 0
    timeout = time.time() + timeout
    refresh_count = lambda_invocation_count(function_name, start_time)

    while start_count == refresh_count:
        if time.time() > timeout:
            raise TimeoutError(f'{function_name} was not invoked')
        time.sleep(5)
        refresh_count = lambda_invocation_count(function_name, start_time)
        log.debug(f'Refresh Count: {refresh_count}')

def get_latest_log_stream_events(log_group: str, start_time=None, end_time=None, stream_limit=2, filter_pattern=" ") -> list:
        '''
        Gets a list of log events within the latest stream of the CloudWatch log group
        
        Arguments:
            log_group: CloudWatch log group name
            start_time:  Start of the time range in milliseconds UTC
            end_time:  End of the time range in milliseconds UTC
            filter_pattern: Pattern used to filter log events (see link for pattern syntax: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html)
        '''
        logs = boto3.client('logs')

        log.debug(f'Log Group: {log_group}')
        streams = [stream['logStreamName'] for stream in logs.describe_log_streams(
            logGroupName=log_group,
            orderBy='LastEventTime',
            descending=True,
            limit=stream_limit
        )['logStreams']]

        log.debug(f'Streams:\n{streams}')
        
        log.info('Getting log stream events')
        if start_time and end_time:
            log.debug(f'Start Time: {start_time}')
            log.debug(f'End Time: {end_time}')
            return logs.filter_log_events(
                logGroupName=log_group,
                logStreamNames=streams,
                filterPattern=filter_pattern,
                startTime=start_time,
                endTime=end_time
            )['events']
        else:
         return logs.filter_log_events(
                logGroupName=log_group,
                logStreamNames=streams,
                filterPattern=filter_pattern
            )['events']


def push(repo_name, branch, files, commit_message='test'):
    '''
    Pushes changes to Github repo using PyGithub

    Arguments:
        repo_name: Repository name
        branch: Pre-existing remote GitHub branch
        files: Dictionary keys containing file paths relative to the repository's root directory and values containing the content within the file path
        commit_message: Commit message used for commit
    '''
    repo = github.Github(os.environ['TF_VAR_testing_github_token']).get_user().get_repo(repo_name)
    elements = []
    head_ref = repo.get_git_ref('heads/' + branch)
    for filepath, content in files.items():
        log.debug(f'Creating file: {filepath}')
        blob = repo.create_git_blob(content, "utf-8")
        elements.append(github.InputGitTreeElement(path=filepath, mode='100644', type='blob', sha=blob.sha))
    head_sha = repo.get_branch(branch).commit.sha
    base_tree = repo.get_git_tree(sha=head_sha)
    tree = repo.create_git_tree(elements, base_tree)
    parent = repo.get_git_commit(sha=head_sha)
    commit_id = repo.create_git_commit(commit_message, tree, [parent]).sha
    head_ref.edit(sha=commit_id)

def pr(repo_name, base, head, files, commit_message='test', title='Test PR', body='test'):
    '''
    Pushes changes to the remote `head` ref and creates a pull request comparing the `head` ref to the `base` ref using PyGithub

    Arguments:
        repo_name: Repository name
        base: Pre-existing remote base ref
        head: Pre-existing remote head ref
        branch: Pre-existing remote GitHub branch
        files: Dictionary keys containing file paths relative to the repository's root directory and values containing the content within the file path
        title: Title of the PR
        body: Body content of the PR
        commit_message: Commit message used for push commit
    '''
    repo = github.Github(os.environ['TF_VAR_testing_github_token']).get_user().get_repo(repo_name)

    base_commit = repo.get_branch(base)
    log.info(f'Creating Branch: {head}')
    repo.create_git_ref(ref='refs/heads/' + head, sha=base_commit.commit.sha)

    log.info('Pushing changes')
    push(repo_name, head, files, commit_message)

    log.info('Creating PR')
    pr = repo.create_pull(title=title, body=body, base=base, head=head)
    log.debug(f'PR #{pr.number}')
    log.debug(f'PR commits: {pr.commits}')
