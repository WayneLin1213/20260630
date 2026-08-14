-- ============================================================
-- 钉钉通知代理函数 - 解决浏览器CORS跨域问题
-- 在 Supabase Dashboard → SQL Editor 中执行此脚本
-- 项目地址: https://supabase.com/dashboard/project/vxxkxaxvwknfafehcruj/sql
-- ============================================================

-- 1. 启用 pg_net 扩展（Postgres 原生异步HTTP客户端，Supabase自带）
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. 异步发送钉钉消息的函数
-- 返回 request_id（bigint），消息在后台异步发送
CREATE OR REPLACE FUNCTION public.send_dingtalk_msg(
    p_webhook TEXT,
    p_secret TEXT,
    p_content TEXT,
    p_at_mobiles TEXT[] DEFAULT '{}'
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_timestamp TEXT;
    v_string_to_sign TEXT;
    v_sign BYTEA;
    v_sign_b64 TEXT;
    v_url TEXT;
    v_body JSONB;
    v_request_id BIGINT;
BEGIN
    -- 生成时间戳和HMAC-SHA256签名
    v_timestamp := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT::TEXT;
    v_string_to_sign := v_timestamp || E'\n' || p_secret;
    v_sign := hmac(v_string_to_sign::TEXT, p_secret, 'sha256');
    v_sign_b64 := replace(
        replace(
            replace(encode(v_sign, 'base64'), '+', '%2B'),
            '=', '%3D'
        ),
        '/', '%2F'
    );

    v_url := p_webhook || '&timestamp=' || v_timestamp || '&sign=' || v_sign_b64;

    -- 构建消息体
    v_body := jsonb_build_object(
        'msgtype', 'text',
        'text', jsonb_build_object('content', p_content),
        'at', CASE
            WHEN array_length(p_at_mobiles, 1) > 0
            THEN jsonb_build_object('atMobiles', p_at_mobiles, 'isAtAll', false)
            ELSE jsonb_build_object('isAtAll', true)
        END
    );

    -- 异步发送 HTTP POST（不等待响应）
    SELECT net.http_post(
        url := v_url,
        body := v_body::TEXT::BYTEA,
        headers := jsonb_build_object('Content-Type', 'application/json')
    ) INTO v_request_id;

    RETURN v_request_id;
END;
$$;

-- 3. 授予匿名用户执行权限（看板前端使用anon key）
GRANT EXECUTE ON FUNCTION public.send_dingtalk_msg(TEXT, TEXT, TEXT, TEXT[]) TO anon, authenticated;

-- ============================================================
-- 执行完成后，可在SQL Editor中运行以下命令测试：
-- ============================================================
-- SELECT public.send_dingtalk_msg(
--     'https://oapi.dingtalk.com/robot/send?access_token=86220d685a21b6b2d4286888c566dd20e4c69c85ff98db45cdf53283eeb598f8',
--     'SECa9f4b94c79b6d6cea3953528869132e38ddf8ee756fa5588bd10428a9758bad8',
--     '🔧 数据库代理测试成功 - 交期通知',
--     '{}'::TEXT[]
-- );
-- 如果返回一个数字（request_id），说明函数创建成功且消息已发出。
-- 检查钉钉群是否收到测试消息。
