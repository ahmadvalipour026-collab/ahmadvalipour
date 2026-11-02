-- Public bootstrap endpoint only needs the building name for the login screen.
-- Never enumerate residents, unit numbers, or administrator accounts anonymously.
CREATE OR REPLACE FUNCTION public.app_public_info()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT jsonb_build_object(
    'building_name',
    coalesce((SELECT s.value FROM public.settings s WHERE s.key = 'building_name'), 'ساختمان')
  );
$function$;

-- These legacy auth.uid()-based helpers are not used by the custom-session PWA.
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.my_unit() FROM PUBLIC, anon, authenticated;
