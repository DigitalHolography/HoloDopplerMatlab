classdef ParallelPoolManager < handle
% Gère un pool parallèle partagé avec comptage de références
% Évite de créer/détruire des pools à chaque appel

properties (Access = private)
    PoolObj = []
    RefCount = 0
    RequestedWorkers = 0
end

properties (Dependent)
    Pool % Pool object (read-only)
    NumWorkers % Number of workers in the pool
end

methods

    function obj = ParallelPoolManager(defaultWorkers)
        % Constructeur
        %   defaultWorkers - nombre de workers souhaité (défaut: auto)
        if nargin < 1
            defaultWorkers = obj.getRecommendedWorkers();
        end

        obj.RequestedWorkers = max(defaultWorkers, 0);
    end

    function acquire(obj, numWorkers)
        % Acquiert un pool parallèle
        %   numWorkers - (optionnel) nombre de workers à utiliser
        if nargin >= 2
            obj.RequestedWorkers = max(numWorkers, 0);
        end

        if obj.RequestedWorkers <= 0
            fprintf('ParallelPoolManager: Serial mode (workers = 0)\n');
            return
        end

        existingPool = gcp('nocreate');

        if isempty(existingPool)
            % Créer un nouveau pool
            try
                obj.PoolObj = parpool(obj.RequestedWorkers);
                obj.RefCount = 1;
                fprintf('ParallelPoolManager: Created new pool with %d workers\n', ...
                    obj.RequestedWorkers);
            catch ME
                warning(ME.identifier, 'ParallelPoolManager: Failed to create pool: %s', ME.message);
                fprintf('ParallelPoolManager: Falling back to serial mode\n');
                obj.PoolObj = [];
                obj.RefCount = 0;
            end

        else
            % Utiliser le pool existant
            obj.PoolObj = existingPool;
            obj.RefCount = obj.RefCount + 1;

            if existingPool.NumWorkers ~= obj.RequestedWorkers
                warning('ParallelPoolManager: Using existing pool with %d workers (requested %d)', ...
                    existingPool.NumWorkers, obj.RequestedWorkers);
            else
                fprintf('ParallelPoolManager: Reusing existing pool (refcount=%d)\n', obj.RefCount);
            end

        end

    end

    function release(obj)
        % Libère le pool (décrémente le compteur)
        if obj.RefCount <= 0
            return
        end

        obj.RefCount = obj.RefCount - 1;

        % Ne fermer le pool que si plus personne ne l'utilise
        if obj.RefCount == 0 && ~isempty(obj.PoolObj) && isvalid(obj.PoolObj)

            try
                delete(obj.PoolObj);
                fprintf('ParallelPoolManager: Closed pool (no more references)\n');
            catch
                % Ignorer les erreurs de fermeture
            end

            obj.PoolObj = [];
        end

    end

    function pool = get.Pool(obj)
        pool = obj.PoolObj;
    end

    function n = get.NumWorkers(obj)

        if ~isempty(obj.PoolObj) && isvalid(obj.PoolObj)
            n = obj.PoolObj.NumWorkers;
        else
            n = 0;
        end

    end

    function tf = isAvailable(obj)
        tf = ~isempty(obj.PoolObj) && isvalid(obj.PoolObj);
    end

end

methods (Static)

    function n = getRecommendedWorkers()
        % Recommande un nombre de workers (laisse 1-2 cores libres)
        try
            localCluster = parcluster('local');
            maxWorkers = localCluster.NumWorkers;
            n = max(1, min(10, maxWorkers - 1)); % Au moins 1, au plus 10
        catch
            n = 4; % Valeur par défaut raisonnable
        end

    end

end

methods (Access = private)

    function delete(obj)
        obj.release();
    end

end

end
