from diagrams import Cluster, Diagram, Edge
from diagrams.aws.network import APIGateway
from diagrams.aws.compute import LambdaFunction
from diagrams.aws.management import SystemsManagerParameterStore
from diagrams.aws.devtools import Codebuild

common_attr = {"fontsize": "15", "fontname": "Times bold"}


with Diagram("terraform-aws-dynamic-github-source", graph_attr=common_attr):
    validator = LambdaFunction("Validate Requests", **common_attr)
    runner = LambdaFunction("Starts CodeBuild project\nwith override config", labelloc="t", **common_attr)
    codebuild = Codebuild("Build", **common_attr)

    APIGateway("Webhook Event", **common_attr) >> validator >> runner >> codebuild
