import '../../../../core/presentation/watch_cubit.dart';
import '../../domain/contractor.dart';
import '../../domain/work_job.dart';

/// Live job list view model (all jobs; screens filter by role/status).
typedef JobsCubit = WatchCubit<List<WorkJob>>;

/// Live contractor list view model.
typedef ContractorsCubit = WatchCubit<List<Contractor>>;
