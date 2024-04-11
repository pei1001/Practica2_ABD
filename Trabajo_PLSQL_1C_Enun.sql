drop table clientes cascade constraints;
drop table abonos   cascade constraints;
drop table eventos  cascade constraints;
drop table reservas	cascade constraints;

drop sequence seq_abonos;
drop sequence seq_eventos;
drop sequence seq_reservas;


-- Creación de tablas y secuencias

create table clientes(
	NIF	varchar(9) primary key,
	nombre	varchar(20) not null,
	ape1	varchar(20) not null,
	ape2	varchar(20) not null
);


create sequence seq_abonos;

create table abonos(
	id_abono	integer primary key,
	cliente  	varchar(9) references clientes,
	saldo	    integer not null check (saldo>=0)
    );

create sequence seq_eventos;

create table eventos(
	id_evento	integer  primary key,
	nombre_evento		varchar(20),
    fecha       date not null,
	asientos_disponibles	integer  not null
);

create sequence seq_reservas;

create table reservas(
	id_reserva	integer primary key,
	cliente  	varchar(9) references clientes,
    evento      integer references eventos,
	abono       integer references abonos,
	fecha	date not null
);


	
-- Procedimiento a implementar para realizar la reserva
create or replace procedure reservar_evento( arg_NIF_cliente varchar,
 arg_nombre_evento varchar, arg_fecha date) is
    pragma autonomous_transaction; -- Marcar la transacción como autónoma para tener un nivel de aislamiento de transacción independiente
    v_evento_pasado EXCEPTION;
    PRAGMA EXCEPTION_INIT(v_evento_pasado, -20001);
    v_evento_id eventos.id_evento%TYPE;
    v_saldo_abono abonos.saldo%TYPE;
    v_asientos_disponibles eventos.asientos_disponibles%TYPE;
    v_reserva_id reservas.id_reserva%TYPE;
begin
    -- Establecer el nivel de aislamiento de transacción a SERIALIZABLE
    execute immediate 'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE';

    -- Iniciar la transacción
    begin
        -- Bloquear la fila correspondiente al evento para escritura
        select id_evento, fecha, asientos_disponibles
        into v_evento_id, v_asientos_disponibles, v_evento_fecha
        from eventos
        where nombre_evento = arg_nombre_evento
        for update nowait; -- Bloqueo exclusivo sin esperar

        -- Comprobar si el evento ya pasó
        if v_evento_fecha < sysdate then
            raise_application_error(-20001, 'No se pueden reservar eventos pasados.');
        end if;

        -- Comprobar si el evento existe
        if v_evento_id is null then
            raise_application_error(-20003, 'El evento ' || arg_nombre_evento || ' no existe.');
        end if;

        -- Bloquear la fila correspondiente al cliente para escritura
        select saldo
        into v_saldo_abono
        from abonos
        where cliente = arg_NIF_cliente
        for update nowait; -- Bloqueo exclusivo sin esperar

        -- Comprobar si el cliente existe
        if v_saldo_abono is null then
            raise_application_error(-20002, 'Cliente inexistente.');
        end if;

        -- Comprobar si hay asientos disponibles y el cliente tiene saldo suficiente
        if v_asientos_disponibles <= 0 then
            raise_application_error(-20005, 'No hay asientos disponibles para el evento.');
        elsif v_saldo_abono <= 0 then
            raise_application_error(-20004, 'Saldo en abono insuficiente.');
        end if;

        -- Actualizar el saldo del abono del cliente
        update abonos
        set saldo = saldo - 1
        where cliente = arg_NIF_cliente;

        -- Actualizar el número de plazas disponibles para el evento
        update eventos
        set asientos_disponibles = asientos_disponibles - 1
        where id_evento = v_evento_id;

        -- Obtener el próximo ID de reserva
        select seq_reservas.nextval into v_reserva_id from dual;

        -- Insertar la reserva en la tabla de reservas
        insert into reservas(id_reserva, cliente, evento, abono, fecha)
        values (v_reserva_id, arg_NIF_cliente, v_evento_id, v_saldo_abono, arg_fecha);

    exception
        when others then
            rollback; -- Deshacer la transacción en caso de error
            raise;
    end;

    -- Confirmar la transacción
    commit;
end;
/


------ Deja aquí tus respuestas a las preguntas del enunciado:
-- * P4.1: Sí, la comprobación hecha en el paso 2 seguirá siendo fiable al realizar las operaciones en una misma transacción evitando así problemas manejando 
-- el control de concurrencia. En el paso 2 se comprueban los campos necesarios para poder realizar la reserva y en el paso 3 las acciones necesarias para 
-- llevarla a cabo con los bloqueos necesarios para evitar problemas.
	
-- * P4.2: Gracias a haber añadido al código el nivel de aislamiento serializable y el uso de bloqueos exclusivos, junto con el manejo adecuado de las excepciones,	
-- no sería posible posible que se agreguen reservas no recogidas gracias a la rigurosidad y la garantía de consistencia proporcionadas por estas medidas.
	
-- * P4.3: La estrategia de programación usada se basa en el enfoque de control de concurrencia y transacciones atómicas.
--
-- * P4.4: Se puede apreciar en el código en las consultas select al usar la cláusula FOR UPDATE para adquirir bloqueos exclusivos, se usa autonomous_transaction 
-- para iniciar una transacción separada e independiente de la principal que lo llama, se usan las expeciones y el rollback para que en caso de que se detecte una
-- excepción se deshagan todas las operaciones realizadas.	
	
-- * P4.5: Otra opción para solucionar el problema tratado sería utilizar un enfoque basado en colas o bloqueos a nivel de aplicación para coordinar las operaciones 
-- de reserva y evitar los problemas de concurrencia. 
-- PSEUDOCÓDIGO
-- Procedimiento reservar_evento(arg_NIF_cliente, arg_nombre_evento, arg_fecha):
--    // Adquirir un bloqueo a nivel de aplicación para coordinar las operaciones de reserva
--    adquirir_bloqueo_aplicacion()

--    // Verificar la disponibilidad de asientos y el saldo del abono
--    si asientos_disponibles < 1 o saldo_abono < 1:
--        liberar_bloqueo_aplicacion()
--        devolver error

--    // Realizar la reserva
--    actualizar_saldo_abono()
--    actualizar_asientos_disponibles()
--    crear_reserva()

--    // Liberar el bloqueo a nivel de aplicación
--    liberar_bloqueo_aplicacion()

Fin del procedimiento

create or replace
procedure reset_seq( p_seq_name varchar )
is
    l_val number;
begin
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    execute immediate
    'alter sequence ' || p_seq_name || ' increment by -' || l_val || 
                                                          ' minvalue 0';
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    execute immediate
    'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';

end;
/


create or replace procedure inicializa_test is
begin
  reset_seq( 'seq_abonos' );
  reset_seq( 'seq_eventos' );
  reset_seq( 'seq_reservas' );
        
  
    delete from reservas;
    delete from eventos;
    delete from abonos;
    delete from clientes;
    
       
		
    insert into clientes values ('12345678A', 'Pepe', 'Perez', 'Porras');
    insert into clientes values ('11111111B', 'Beatriz', 'Barbosa', 'Bernardez');
    
    insert into abonos values (seq_abonos.nextval, '12345678A',10);
    insert into abonos values (seq_abonos.nextval, '11111111B',0);
    
    insert into eventos values ( seq_eventos.nextval, 'concierto_la_moda', date '2024-6-27', 200);
    insert into eventos values ( seq_eventos.nextval, 'teatro_impro', date '2024-7-1', 50);

    commit;
end;
/

exec inicializa_test;

-- Completa el test

create or replace procedure test_reserva_evento is
begin
	 
  --caso 1 Reserva correcta, se realiza
  begin
    reservar_evento('12345678A', 'concierto_la_moda', date '2024-6-27');
    dbms_output.put_line('Caso 1: Reserva correcta, se realizó.');
  exception
    when others then
        dbms_output.put_line('Caso 1: Error - ' || SQLCODE || ': ' || SQLERRM);
  end;
  
  --caso 2 Evento pasado
  begin
    reservar_evento('12345678A', 'concierto_la_moda', date '2023-6-27');
    dbms_output.put_line('Caso 2: Error - No se pueden reservar eventos pasados (No se lanzó la excepción esperada).');
  exception
    when others then
        if SQLCODE = -20001 then
            dbms_output.put_line('Caso 2: Excepción esperada - ' || SQLCODE || ': ' || SQLERRM);
        else
            dbms_output.put_line('Caso 2: Error - ' || SQLCODE || ': ' || SQLERRM);
        end if;
  end;
  
  --caso 3 Evento inexistente
  begin
    reservar_evento('12345678A', 'evento_inexistente', date '2024-6-27');
    dbms_output.put_line('Caso 3: Error - El evento no existe (No se lanzó la excepción esperada).');
  exception
    when others then
        if SQLCODE = -20003 then
            dbms_output.put_line('Caso 3: Excepción esperada - ' || SQLCODE || ': ' || SQLERRM);
        else
            dbms_output.put_line('Caso 3: Error - ' || SQLCODE || ': ' || SQLERRM);
        end if;
  end;
  
  --caso 4 Cliente inexistente  
  begin
    reservar_evento('cliente_inexistente', 'concierto_la_moda', date '2024-6-27');
    dbms_output.put_line('Caso 4: Error - Cliente inexistente (No se lanzó la excepción esperada).');
  exception
    when others then
        if SQLCODE = -20002 then
            dbms_output.put_line('Caso 4: Excepción esperada - ' || SQLCODE || ': ' || SQLERRM);
        else
            dbms_output.put_line('Caso 4: Error - ' || SQLCODE || ': ' || SQLERRM);
        end if;
  end;
  
  --caso 5 El cliente no tiene saldo suficiente
  begin
    reservar_evento('11111111B', 'concierto_la_moda', date '2024-6-27');
    dbms_output.put_line('Caso 5: Error - Saldo en abono insuficiente (No se lanzó la excepción esperada).');
  exception
    when others then
        if SQLCODE = -20004 then
            dbms_output.put_line('Caso 5: Excepción esperada - ' || SQLCODE || ': ' || SQLERRM);
        else
            dbms_output.put_line('Caso 5: Error - ' || SQLCODE || ': ' || SQLERRM);
        end if;
  end;
end;
/



set serveroutput on;
exec test_reserva_evento;
