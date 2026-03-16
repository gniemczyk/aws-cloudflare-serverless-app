import json
import boto3
import os
import base64

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('TABLE_NAME', 'BusinessCards'))

def handler(event, context):
    # Logowanie dla CloudWatch
    print(f"DEBUG EVENT: {json.dumps(event)}")

    # 1. Pobieranie metody
    method = event.get('httpMethod')
    if not method:
        method = event.get('requestContext', {}).get('http', {}).get('method', 'GET')

    # 2. Pobieranie i czyszczenie ścieżki (do routingu używamy lower, ale do maila użyjemy raw_path)
    raw_path = event.get('rawPath') or event.get('path') or '/'
    path = raw_path.lower().rstrip('/')
    if path == "": path = "/"

    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,POST,GET,DELETE',
        'Content-Type': 'application/json'
    }

    try:
        # Obsługa CORS
        if method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({'message': 'CORS OK'})
            }
        # ENDPOINT: /hello
        if path == '/hello':
            return {'statusCode': 200, 'headers': headers, 'body': json.dumps({'message': 'Hello!'})}

        # ENDPOINT: /adduser
        elif path == '/adduser':
            if method != 'POST':
                return {'statusCode': 405, 'headers': headers, 'body': json.dumps({'error': 'Użyj POST'})}

            body_raw = event.get('body', '{}')
            if event.get('isBase64Encoded', False):
                body_raw = base64.b64decode(body_raw).decode('utf-8')
            body = json.loads(body_raw)

            table.put_item(Item={
                'CardID': body['email'],
                'Name': body.get('name', ''),
                'Surname': body.get('surname', ''),
                'Company': body.get('company', ''),
                'Role': body.get('role', 'DevOps')
            })
            return {'statusCode': 201, 'headers': headers, 'body': json.dumps({'message': 'Dodano', 'email': body['email']})}

        # ENDPOINT: /getuser
        elif path == '/getuser' or path.startswith('/getuser/'):
            if method != 'GET':
                return {'statusCode': 405, 'headers': headers, 'body': json.dumps({'error': 'Użyj GET'})}

            # Wyciąganie maila na podstawie oryginalnej ścieżki (aby zachować wielkość liter)
            # Rozbicie ['/', 'getuser', 'mail@test.pl']
            parts = raw_path.rstrip('/').split('/')
            email_to_find = parts[2] if len(parts) > 2 else None

            if email_to_find:
                # Szukanie konkretnego użytkownika
                res = table.get_item(Key={'CardID': email_to_find})
                if 'Item' in res:
                    return {'statusCode': 200, 'headers': headers, 'body': json.dumps(res['Item'])}
                return {'statusCode': 404, 'headers': headers, 'body': json.dumps({'error': 'Nie znaleziono'})}

            # Brak maila w URL - pobierz wszystkich
            res = table.scan()
            return {'statusCode': 200, 'headers': headers, 'body': json.dumps(res.get('Items', []))}

        # ENDPOINT: /deleteuser
        elif path == '/deleteuser' or path.startswith('/deleteuser/'):
            if method != 'DELETE':
                return {'statusCode': 405, 'headers': headers, 'body': json.dumps({'error': 'Użyj DELETE'})}

            # Wyciąganie maila do usunięcia
            parts = raw_path.rstrip('/').split('/')
            email_to_del = parts[2] if len(parts) > 2 else None

            if not email_to_del:
                return {'statusCode': 400, 'headers': headers, 'body': json.dumps({'error': 'Brak maila w URL'})}

            table.delete_item(Key={'CardID': email_to_del})
            return {'statusCode': 200, 'headers': headers, 'body': json.dumps({'message': f'Usunieto {email_to_del}'})}

        # DOMYŚLNE
        return {'statusCode': 404, 'headers': headers, 'body': json.dumps({'error': f'Brak sciezki {path}'})}

    except Exception as e:
        return {'statusCode': 500, 'headers': headers, 'body': json.dumps({'error': str(e)})}
