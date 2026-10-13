import '../../../../core/presentation/watch_cubit.dart';
import '../../domain/contractor.dart';
import '../../domain/work_job.dart';

typedef JobsCubit = WatchCubit<List<WorkJob>>;

typedef ContractorsCubit = WatchCubit<List<Contractor>>;
