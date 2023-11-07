resource "aws_iam_user" "airbyte_user" {
  name = "airbyte_user"
}

resource "aws_iam_access_key" "airbyte_user" {
  user = aws_iam_user.airbyte_user.name
}

data "aws_iam_policy_document" "airbyte_user" {
  statement {
    sid = "1"
    actions = [
      "s3:*",
    ]
    resources = [
      "arn:aws:s3:::${target_bucket_name}/*",
    ]
  }
}

resource "aws_iam_user_policy" "airbyte_user" {
  name   = "airbyte_user"
  user   = aws_iam_user.airbyte_user.name
  policy = data.aws_iam_policy_document.airbyte_user.json
}